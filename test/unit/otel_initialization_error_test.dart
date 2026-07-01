// Licensed under the Apache License, Version 2.0
// Copyright 2025, Michael Bushe, All rights reserved.

// Regression coverage for the factory-upgrade lifecycle (issue #50).
//
// The API auto-installs a spec-mandated no-op factory the first time any API
// call runs. When that happens before OTel.initialize(), the SDK must replace
// that no-op factory with a real SDK factory rather than crash with an opaque
// "APITracerProvider is not a subtype of TracerProvider" cast error or refuse
// to initialize. This mirrors how OpenTelemetry SDKs replace the global no-op
// provider when the SDK is installed.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:dartastic_opentelemetry_api/dartastic_opentelemetry_api.dart'
    as api;
import 'package:test/test.dart';

void main() {
  tearDown(() async {
    await OTel.reset();
  });

  group('SDK accessors upgrade the API no-op factory instead of throwing', () {
    test('tracerProvider() still requires initialize() if no factory exists',
        () {
      expect(
        OTel.tracerProvider,
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('OTel.initialize() must be called first'),
        )),
      );
      expect(OTelFactory.otelFactory, isNull);
      expect(OTel.isInitialized, isFalse);
    });

    test('tracerProvider() after API auto-install does not crash (issue #50)',
        () {
      // Force the API to win the "first factory installed" race.
      final apiProvider = api.OTelAPI.tracerProvider();
      expect(apiProvider, isA<api.APITracerProvider>());
      expect(OTelFactory.otelFactory, isA<api.OTelAPIFactory>());
      expect(OTelFactory.otelFactory, isNot(isA<OTelSDKFactory>()));

      // The previously-failing path: OTelAPI.tracerProvider() as TracerProvider.
      final tp = OTel.tracerProvider();
      expect(tp, isA<TracerProvider>());
      expect(OTelFactory.otelFactory, isA<OTelSDKFactory>());
      expect(OTel.isInitialized, isFalse);

      // The API cache should notice the swapped global factory on its next call.
      expect(api.OTelAPI.tracerProvider(), isA<TracerProvider>());
    });

    test('meterProvider() after API auto-install returns an SDK MeterProvider',
        () {
      api.OTelAPI.meterProvider();
      expect(OTelFactory.otelFactory, isNot(isA<OTelSDKFactory>()));

      expect(OTel.meterProvider(), isA<MeterProvider>());
      expect(OTelFactory.otelFactory, isA<OTelSDKFactory>());
    });

    test(
        'loggerProvider() after API auto-install returns an SDK LoggerProvider',
        () {
      api.OTelAPI.loggerProvider();
      expect(OTelFactory.otelFactory, isNot(isA<OTelSDKFactory>()));

      expect(OTel.loggerProvider(), isA<LoggerProvider>());
      expect(OTelFactory.otelFactory, isA<OTelSDKFactory>());
    });

    test('addTracerProvider() after API auto-install returns an SDK provider',
        () {
      api.OTelAPI.tracerProvider();
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
      expect(OTel.meterProvider(), isA<MeterProvider>());
    });

    test('initialize() succeeds after API loggerProvider()', () async {
      api.OTelAPI.loggerProvider();
      await OTel.initialize(serviceName: 'svc-c');
      expect(OTel.isInitialized, isTrue);
      expect(OTel.loggerProvider(), isA<LoggerProvider>());
    });

    test(
        'initialize() after an API-noop upgrade still applies configured resource',
        () async {
      api.OTelAPI.tracerProvider();
      OTel.tracerProvider();
      expect(OTelFactory.otelFactory, isA<OTelSDKFactory>());
      expect(OTel.isInitialized, isFalse);

      await OTel.initialize(serviceName: 'configured-service');

      final hasServiceName = OTel.defaultResource!.attributes.toList().any(
            (a) => a.key == 'service.name' && a.value == 'configured-service',
          );
      expect(hasServiceName, isTrue);
      expect(OTel.isInitialized, isTrue);
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
