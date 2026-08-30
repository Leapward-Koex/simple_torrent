package com.leapwardkoex.simple_torrent.simple_torrent

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CountDownLatch
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue
import org.mockito.Mockito.mock
import org.mockito.Mockito.verify
import org.mockito.Mockito.verifyNoInteractions

internal class SimpleTorrentPluginTest {
    @Test
    fun finaliseRunsOffCallerAndCompletesOnlyOnPlatformDispatcher() {
        val platformCallbacks = LinkedBlockingQueue<() -> Unit>()
        val operationFinished = CountDownLatch(1)
        val destroyFinished = CountDownLatch(1)
        val callingThread = Thread.currentThread().id
        var operationThread = callingThread
        var completionThread = -1L
        var completionCode = -1
        var completionCount = 0
        val worker = NativeFinaliseWorker(platformCallbacks::add)

        assertTrue(worker.submit(
            operation = {
                operationThread = Thread.currentThread().id
                operationFinished.countDown()
                2
            },
            completion = { code ->
                completionThread = Thread.currentThread().id
                completionCode = code
                completionCount += 1
            },
        ))

        assertTrue(operationFinished.await(5, TimeUnit.SECONDS))
        assertNotEquals(callingThread, operationThread)
        assertEquals(0, completionCount)
        platformCallbacks.poll(5, TimeUnit.SECONDS)!!.invoke()
        assertEquals(callingThread, completionThread)
        assertEquals(2, completionCode)
        assertEquals(1, completionCount)

        worker.close { destroyFinished.countDown() }
        assertTrue(destroyFinished.await(5, TimeUnit.SECONDS))
    }

    @Test
    fun closeWaitsBehindInflightFinaliseAndRejectsNewWork() {
        val platformCallbacks = LinkedBlockingQueue<() -> Unit>()
        val operationStarted = CountDownLatch(1)
        val allowOperationToFinish = CountDownLatch(1)
        val destroyFinished = CountDownLatch(1)
        val order = mutableListOf<String>()
        val worker = NativeFinaliseWorker(platformCallbacks::add)

        assertTrue(worker.submit(
            operation = {
                synchronized(order) { order += "finalise-start" }
                operationStarted.countDown()
                assertTrue(allowOperationToFinish.await(5, TimeUnit.SECONDS))
                synchronized(order) { order += "finalise-end" }
                0
            },
            completion = {},
        ))
        assertTrue(operationStarted.await(5, TimeUnit.SECONDS))

        worker.close {
            synchronized(order) { order += "destroy" }
            destroyFinished.countDown()
        }
        assertFalse(worker.submit(operation = { 0 }, completion = {}))
        assertFalse(destroyFinished.await(100, TimeUnit.MILLISECONDS))

        allowOperationToFinish.countDown()
        assertTrue(destroyFinished.await(5, TimeUnit.SECONDS))
        assertEquals(
            listOf("finalise-start", "finalise-end", "destroy"),
            synchronized(order) { order.toList() },
        )
        platformCallbacks.poll(5, TimeUnit.SECONDS)!!.invoke()
    }

    @Test
    fun workerConvertsThrownFinaliseToSingleTypedNativeErrorCode() {
        val platformCallbacks = LinkedBlockingQueue<() -> Unit>()
        val destroyFinished = CountDownLatch(1)
        val codes = mutableListOf<Int>()
        val worker = NativeFinaliseWorker(platformCallbacks::add)

        assertTrue(worker.submit(
            operation = { error("native bridge failure") },
            completion = codes::add,
        ))
        platformCallbacks.poll(5, TimeUnit.SECONDS)!!.invoke()

        assertEquals(listOf(6), codes)
        worker.close { destroyFinished.countDown() }
        assertTrue(destroyFinished.await(5, TimeUnit.SECONDS))
    }

    @Test
    fun methodCallBeforeAttachmentReturnsTypedError() {
        val plugin = SimpleTorrentPlugin()
        val result = mock(MethodChannel.Result::class.java)

        plugin.onMethodCall(MethodCall("init", emptyMap<String, Any>()), result)

        verify(result).error(
            "not_initialized",
            "Native manager is not available",
            null,
        )
    }

    @Test
    fun suspensionArgumentAcceptsOnlyBooleanValuesIncludingFalse() {
        val plugin = SimpleTorrentPlugin()
        val result = mock(MethodChannel.Result::class.java)
        val values = mutableListOf<Boolean>()

        plugin.withSuspendedArgument(
            MethodCall("setTransfersSuspended", mapOf("suspended" to true, "extra" to 1)),
            result,
            values::add,
        )
        plugin.withSuspendedArgument(
            MethodCall("setTransfersSuspended", mapOf("suspended" to false)),
            result,
            values::add,
        )

        assertEquals(listOf(true, false), values)
        verifyNoInteractions(result)
    }

    @Test
    fun suspensionArgumentRejectsMissingNullNonMapAndNonBooleanValues() {
        val plugin = SimpleTorrentPlugin()
        val invalidArguments = listOf<Any?>(
            null,
            "not a map",
            emptyMap<String, Any>(),
            mapOf<String, Any?>("suspended" to null),
            mapOf("suspended" to 1),
            mapOf("suspended" to "true"),
        )

        for (arguments in invalidArguments) {
            val result = mock(MethodChannel.Result::class.java)
            var invoked = false

            plugin.withSuspendedArgument(
                MethodCall("setTransfersSuspended", arguments),
                result,
            ) { invoked = true }

            assertFalse(invoked)
            verify(result).error(
                "invalid_argument",
                "suspended must be a boolean",
                null,
            )
        }
    }

    @Test
    fun nativeQueryPreservesNotFoundCode() {
        val plugin = SimpleTorrentPlugin()
        val result = mock(MethodChannel.Result::class.java)

        plugin.completeNativeQuery(
            mapOf("code" to 2),
            result,
            String::class.java,
        )

        verify(result).error(
            "torrent_not_found",
            "Native operation failed: torrent_not_found",
            null,
        )
    }

    @Test
    fun nativeQueryPreservesNativeErrorCode() {
        val plugin = SimpleTorrentPlugin()
        val result = mock(MethodChannel.Result::class.java)

        plugin.completeNativeQuery(
            mapOf("code" to 6),
            result,
            String::class.java,
        )

        verify(result).error(
            "native_error",
            "Native operation failed: native_error",
            null,
        )
    }

    @Test
    fun nativeQueryRetainsFalseAsSuccessfulDomainValue() {
        val plugin = SimpleTorrentPlugin()
        val result = mock(MethodChannel.Result::class.java)

        plugin.completeNativeQuery(
            mapOf("code" to 0, "value" to false),
            result,
            Boolean::class.javaObjectType,
        )

        verify(result).success(false)
    }

    @Test
    fun nativeQueryTransformsEmptyIdsAsSuccessfulDomainValue() {
        val plugin = SimpleTorrentPlugin()
        val result = mock(MethodChannel.Result::class.java)

        plugin.completeNativeQuery(
            mapOf("code" to 0, "value" to intArrayOf()),
            result,
            IntArray::class.java,
        ) { (it as IntArray).toList() }

        verify(result).success(emptyList<Int>())
    }

    @Test
    fun malformedNativeQueryIsNotReportedAsMissingTorrent() {
        val plugin = SimpleTorrentPlugin()
        val result = mock(MethodChannel.Result::class.java)

        plugin.completeNativeQuery(
            mapOf("code" to 0),
            result,
            String::class.java,
        )

        verify(result).error(
            "native_error",
            "Invalid query value from native runtime",
            null,
        )
    }
}
