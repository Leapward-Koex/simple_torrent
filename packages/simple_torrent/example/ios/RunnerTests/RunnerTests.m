// Copyright 2026 Leapward-Koex. All rights reserved.

@import XCTest;
@import integration_test;

// Runs the Dart integration target inside the app-hosted XCTest process. This
// avoids relying on Flutter's iOS Simulator unified-log parser to discover the
// VM service, while still reporting every Dart test through XCTest.
INTEGRATION_TEST_IOS_RUNNER(RunnerIntegrationTests)
