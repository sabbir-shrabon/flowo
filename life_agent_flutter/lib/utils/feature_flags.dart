class FeatureFlags {
  /// Toggle for Phase 1: Fix infinite loading caused by stream deadlock.
  /// If true, uses immediate `ConnectivityService().hasInternet()`.
  /// If false, uses old `ref.read(connectivityProvider.future)`.
  static const bool useNewConnectivityCheck = true;

  /// Toggle for Phase 2: Use optimized V2 backend endpoints.
  /// If true, calls /v2 endpoints (single-query plan detail, server-side today logic).
  /// If false, calls original V1 endpoints (N+1 queries, client-side today logic).
  static const bool useV2Endpoints = true;
}
