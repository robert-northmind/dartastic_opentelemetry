// Licensed under the Apache License, Version 2.0
// Copyright 2025, Michael Bushe, All rights reserved.

// Regression coverage for the lifecycle errors surfaced by the SDK's
// OTel accessors. Calling any SDK provider before OTel.initialize() must
// produce a clear StateError (not an opaque type-cast crash from the
// API's spec-mandated no-op factory leaking through).

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:dartastic_opentelemetry_api/dartastic_opentelemetry_api.dart'
    as api;
import 'package:test/test.dart';

void main() {
  tearDown(() async {
    await OTel.reset();
  });

  test('tracerProvider() before initialize() throws clear StateError', () {
    expect(
      () => OTel.tracerProvider(),
      throwsA(isA<StateError>().having(
        (e) => e.message,
        'message',
        contains('OTel.initialize() must be called first'),
      )),
    );
  });

  test('tracerProvider() after API auto-install names the offending factory',
      () {
    api.OTelAPI.tracerProvider();
    expect(
      () => OTel.tracerProvider(),
      throwsA(isA<StateError>().having(
        (e) => e.message,
        'message',
        contains('auto-installed a no-op factory'),
      )),
    );
  });

  test('meterProvider() before initialize() throws the same clear error', () {
    expect(
      () => OTel.meterProvider(),
      throwsA(isA<StateError>().having(
        (e) => e.message,
        'message',
        contains('OTel.initialize() must be called first'),
      )),
    );
  });

  test('addTracerProvider() before initialize() throws the same clear error',
      () {
    expect(
      () => OTel.addTracerProvider('named'),
      throwsA(isA<StateError>().having(
        (e) => e.message,
        'message',
        contains('OTel.initialize() must be called first'),
      )),
    );
  });
}
