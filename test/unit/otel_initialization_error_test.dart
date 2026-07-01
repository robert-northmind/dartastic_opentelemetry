// Licensed under the Apache License, Version 2.0
// Copyright 2025, Michael Bushe, All rights reserved.

// Regression coverage for the factory-upgrade lifecycle (issue #50).
//
// The API auto-installs a spec-mandated no-op factory the first time any API
// call runs (for example during resource detection). When that happens before
// OTel.initialize(), the SDK must *upgrade* that no-op factory to a real SDK
// factory rather than crash with an opaque
// "APITracerProvider is not a subtype of TracerProvider" cast error or refuse
// to initialize. This mirrors how the Java/JS/Python SDKs replace the global
// no-op provider when the SDK is installed.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:dartastic_opentelemetry_api/dartastic_opentelemetry_api.dart'
    as api;
import 'package:test/test.dart';

void main() {
  tearDown(() async {
    await OTel.reset();
  });

  group('SDK accessors upgrade the API no-op factory instead of throwing', () {
    test('tracerProvider() before initialize() returns an SDK TracerProvider',
        () {
      final tp = OTel.tracerProvider();
      expect(tp, isA<TracerProvider>());
      // The global factory has been upgraded in place...
      expect(OTelFactory.otelFactory, isA<OTelSDKFactory>());
      // ...but this is a provisional upgrade, not an explicit initialize().
      expect(OTel.isInitialized, isFalse);
    });

    test('tracerProvider() after API auto-install does not crash (issue #50)',
        () {
      // Force the API to win the "first factory installed" race.
      api.OTelAPI.tracerProvider();
      expect(OTelFactory.otelFactory, isA<api.OTelAPIFactory>());

      // The previously-failing line: OTelAPI.tracerProvider() as TracerProvider.
      final tp = OTel.tracerProvider();
      expect(tp, isA<TracerProvider>());
      expect(OTelFactory.otelFactory, isA<OTelSDKFactory>());
    });

    test('meterProvider() before initialize() returns an SDK MeterProvider',
        () {
      expect(OTel.meterProvider(), isA<MeterProvider>());
      expect(OTelFactory.otelFactory, isA<OTelSDKFactory>());
    });

    test('loggerProvider() before initialize() returns an SDK LoggerProvider',
        () {
      expect(OTel.loggerProvider(), isA<LoggerProvider>());
      expect(OTelFactory.otelFactory, isA<OTelSDKFactory>());
    });

    test('addTracerProvider() before initialize() returns an SDK provider', () {
      expect(OTel.addTracerProvider('named'), isA<TracerProvider>());
      expect(OTelFactory.otelFactory, isA<OTelSDKFactory>());
    });
  });

  group('initialize() upgrades an already-installed API no-op factory', () {
    test('initialize() succeeds after API tracerProvider()', () async {
      api.OTelAPI.tracerProvider();
      await OTel.initialize(serviceName: 'svc-a');
      expect(OTel.isInitialized, isTrue);
      expect(OTelFactory.otelFactory, isA<OTelSDKFactory>());
    });

    test('initialize() succeeds after API meterProvider()', () async {
      api.OTelAPI.meterProvider();
      await OTel.initialize(serviceName: 'svc-b');
      expect(OTel.isInitialized, isTrue);
    });

    test('initialize() succeeds after API loggerProvider()', () async {
      api.OTelAPI.loggerProvider();
      await OTel.initialize(serviceName: 'svc-c');
      expect(OTel.isInitialized, isTrue);
    });

    test(
        'initialize() after a provisional SDK accessor still applies its config',
        () async {
      // An SDK accessor provisionally upgrades to a default SDK factory.
      OTel.tracerProvider();
      expect(OTel.isInitialized, isFalse);

      // A later initialize() must succeed and install the configured factory.
      await OTel.initialize(serviceName: 'configured-service');
      expect(OTel.isInitialized, isTrue);

      final hasServiceName = OTel.defaultResource!.attributes
          .toList()
          .any((a) => a.key == 'service.name' && a.value == 'configured-service');
      expect(hasServiceName, isTrue);
    });
  });

  group('re-initialization is keyed on an explicit initialize() call', () {
    test('calling initialize() twice throws a clear StateError', () async {
      await OTel.initialize(serviceName: 'first');
      await expectLater(
        OTel.initialize(serviceName: 'second'),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('can only be called once'),
        )),
      );
    });

    test('initialize() works again after reset()', () async {
      await OTel.initialize(serviceName: 'first');
      expect(OTel.isInitialized, isTrue);
      await OTel.reset();
      expect(OTel.isInitialized, isFalse);
      await OTel.initialize(serviceName: 'second');
      expect(OTel.isInitialized, isTrue);
    });
  });
}
