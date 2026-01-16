# MacML: MLOps Platform Architecture

## Executive Summary

MacML is a production-grade MLOps platform designed for macOS with Apple Silicon optimization. The architecture prioritizes offline-first operation, native performance, and seamless scaling from local development to cloud execution.

---

## 1. System Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              MACML SYSTEM                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                         USER INTERFACE LAYER                         │   │
│  │  ┌─────────────────────────────────────────────────────────────┐   │   │
│  │  │              SwiftUI Application (Main Process)              │   │   │
│  │  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────────────┐   │   │   │
│  │  │  │ Run Browser │ │Model Registry│ │  Pipeline Editor   │   │   │   │
│  │  │  └─────────────┘ └─────────────┘ └─────────────────────┘   │   │   │
│  │  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────────────┐   │   │   │
│  │  │  │ Metric Viz  │ │ Log Viewer  │ │   Sync Dashboard   │   │   │   │
│  │  │  └─────────────┘ └─────────────┘ └─────────────────────┘   │   │   │
│  │  └─────────────────────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │ XPC                                    │
│                                    ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                      AGENT DAEMON (LaunchAgent)                      │   │
│  │  ┌───────────────────────────────────────────────────────────────┐  │   │
│  │  │                       CONTROL PLANE                            │  │   │
│  │  │  ┌──────────────┐ ┌──────────────┐ ┌────────────────────┐    │  │   │
│  │  │  │ State Machine│ │ Intent Queue │ │  Sync Coordinator  │    │  │   │
│  │  │  │   Manager    │ │   (Outbox)   │ │                    │    │  │   │
│  │  │  └──────────────┘ └──────────────┘ └────────────────────┘    │  │   │
│  │  │  ┌──────────────┐ ┌──────────────┐ ┌────────────────────┐    │  │   │
│  │  │  │   Conflict   │ │  Idempotency │ │  RBAC / Audit      │    │  │   │
│  │  │  │   Resolver   │ │    Store     │ │    Cache           │    │  │   │
│  │  │  └──────────────┘ └──────────────┘ └────────────────────┘    │  │   │
│  │  └───────────────────────────────────────────────────────────────┘  │   │
│  │  ┌───────────────────────────────────────────────────────────────┐  │   │
│  │  │                        DATA PLANE                              │  │   │
│  │  │  ┌──────────────┐ ┌──────────────┐ ┌────────────────────┐    │  │   │
│  │  │  │  Artifact    │ │    Log       │ │  Metric Stream     │    │  │   │
│  │  │  │  Transfer    │ │  Streamer    │ │    Processor       │    │  │   │
│  │  │  └──────────────┘ └──────────────┘ └────────────────────┘    │  │   │
│  │  │  ┌──────────────┐ ┌──────────────┐ ┌────────────────────┐    │  │   │
│  │  │  │  Backpressure│ │  Bandwidth   │ │  Integrity         │    │  │   │
│  │  │  │  Controller  │ │   Manager    │ │    Verifier        │    │  │   │
│  │  │  └──────────────┘ └──────────────┘ └────────────────────┘    │  │   │
│  │  └───────────────────────────────────────────────────────────────┘  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                        │
│  ┌─────────────────────────────────┴───────────────────────────────────┐   │
│  │                         STORAGE LAYER                                │   │
│  │  ┌───────────────────────┐  ┌─────────────────────────────────┐    │   │
│  │  │    SQLite (WAL)       │  │   Content-Addressed Store       │    │   │
│  │  │  ┌─────────────────┐  │  │  ┌─────────────────────────┐   │    │   │
│  │  │  │ Control State   │  │  │  │   Artifacts (.blob)     │   │    │   │
│  │  │  │ Intent Queue    │  │  │  └─────────────────────────┘   │    │   │
│  │  │  │ Sync Metadata   │  │  │  ┌─────────────────────────┐   │    │   │
│  │  │  │ Run Records     │  │  │  │   Logs (.log.zst)       │   │    │   │
│  │  │  │ Model Registry  │  │  │  └─────────────────────────┘   │    │   │
│  │  │  └─────────────────┘  │  │  ┌─────────────────────────┐   │    │   │
│  │  └───────────────────────┘  │  │   Metrics (.parquet)    │   │    │   │
│  │                              │  └─────────────────────────┘   │    │   │
│  │                              └─────────────────────────────────┘    │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                        │
│                          Network Layer                                      │
│                                    │                                        │
└────────────────────────────────────┼────────────────────────────────────────┘
                                     │
                    ┌────────────────┴────────────────┐
                    │         REMOTE BACKEND          │
                    │  ┌──────────┐  ┌─────────────┐ │
                    │  │ API GW   │  │  Object     │ │
                    │  │ (gRPC)   │  │  Storage    │ │
                    │  └──────────┘  └─────────────┘ │
                    │  ┌──────────┐  ┌─────────────┐ │
                    │  │ K8s      │  │  ML         │ │
                    │  │ Runners  │  │  Registry   │ │
                    │  └──────────┘  └─────────────┘ │
                    └─────────────────────────────────┘
```

---

## 2. Process and Module Layout

### 2.1 Process Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        PROCESS HIERARCHY                                 │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   ┌─────────────────────────────────────────────────────────────────┐  │
│   │  MacML.app (UI Process)                                    │  │
│   │  PID: Dynamic | Sandbox: Yes | Entitlements: UI-focused         │  │
│   │                                                                   │  │
│   │  Responsibilities:                                                │  │
│   │  • SwiftUI rendering and user interaction                        │  │
│   │  • View state management (ephemeral)                             │  │
│   │  • XPC client to agent daemon                                    │  │
│   │  • Async stream consumption for live updates                     │  │
│   │                                                                   │  │
│   │  Memory Budget: 200-500MB (UI state + view cache)                │  │
│   │  CPU Priority: User Interactive                                   │  │
│   └─────────────────────────────────────────────────────────────────┘  │
│                           │                                             │
│                           │ XPC (Mach ports)                            │
│                           ▼                                             │
│   ┌─────────────────────────────────────────────────────────────────┐  │
│   │  com.macml.agent (LaunchAgent Daemon)                      │  │
│   │  PID: Persistent | Sandbox: Yes | Entitlements: Network + FS    │  │
│   │                                                                   │  │
│   │  Responsibilities:                                                │  │
│   │  • All persistent state management                               │  │
│   │  • Network operations (sync, upload, download)                   │  │
│   │  • Background processing and computation                         │  │
│   │  • Local ML execution coordination                               │  │
│   │  • Cache management and eviction                                 │  │
│   │                                                                   │  │
│   │  Memory Budget: 500MB-2GB (based on workload)                    │  │
│   │  CPU Priority: Utility (background), User Initiated (sync)       │  │
│   └─────────────────────────────────────────────────────────────────┘  │
│                           │                                             │
│                           │ Process spawn (optional)                    │
│                           ▼                                             │
│   ┌─────────────────────────────────────────────────────────────────┐  │
│   │  com.macml.mlrunner (On-demand ML Process)                 │  │
│   │  PID: Transient | Sandbox: Strict | Entitlements: GPU + ANE     │  │
│   │                                                                   │  │
│   │  Responsibilities:                                                │  │
│   │  • Core ML inference execution                                   │  │
│   │  • MLX experimental runs                                         │  │
│   │  • Isolated from main agent for stability                        │  │
│   │                                                                   │  │
│   │  Memory Budget: Dynamic (based on model size)                    │  │
│   │  CPU Priority: User Initiated                                    │  │
│   └─────────────────────────────────────────────────────────────────┘  │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Module Architecture (Agent Daemon)

```
com.macml.agent/
├── Core/
│   ├── AgentApp.swift              # Entry point, lifecycle management
│   ├── XPCService.swift            # XPC listener and protocol impl
│   └── Configuration.swift         # Runtime config, feature flags
│
├── ControlPlane/
│   ├── StateMachine/
│   │   ├── RunStateMachine.swift       # Run lifecycle: pending→running→complete
│   │   ├── PipelineStateMachine.swift  # Pipeline orchestration states
│   │   ├── ModelStateMachine.swift     # Model: draft→staged→deployed→archived
│   │   └── StateMachineCoordinator.swift
│   │
│   ├── IntentQueue/
│   │   ├── Intent.swift                # Immutable intent records
│   │   ├── IntentStore.swift           # SQLite-backed durable queue
│   │   ├── IntentProcessor.swift       # Async processing with retry
│   │   └── IdempotencyStore.swift      # Deduplication by intent ID
│   │
│   ├── Sync/
│   │   ├── SyncCoordinator.swift       # Orchestrates sync operations
│   │   ├── IncrementalSync.swift       # Delta sync with vector clocks
│   │   ├── ConflictResolver.swift      # LWW + custom merge strategies
│   │   └── SyncStatusPublisher.swift   # Observable sync state
│   │
│   └── Security/
│       ├── RBACCache.swift             # Offline permission cache
│       ├── AuditLog.swift              # Local audit trail
│       └── TokenManager.swift          # Keychain-backed auth
│
├── DataPlane/
│   ├── Artifacts/
│   │   ├── ArtifactTransfer.swift      # Resumable upload/download
│   │   ├── ChunkedTransfer.swift       # Parallel chunk processing
│   │   ├── TransferQueue.swift         # Priority queue with limits
│   │   └── ProgressTracker.swift       # Per-artifact progress
│   │
│   ├── Streaming/
│   │   ├── LogStreamer.swift           # Real-time log ingestion
│   │   ├── MetricStreamer.swift        # Time-series metric streams
│   │   ├── EventBus.swift              # Internal pub/sub
│   │   └── BackpressureController.swift
│   │
│   └── QoS/
│       ├── BandwidthManager.swift      # Rate limiting, fair queuing
│       ├── NetworkMonitor.swift        # Reachability, connection type
│       └── RetryCoordinator.swift      # Exponential backoff, jitter
│
├── Storage/
│   ├── Database/
│   │   ├── DatabaseManager.swift       # SQLite connection pool
│   │   ├── Migrations.swift            # Schema versioning
│   │   ├── QueryBuilder.swift          # Type-safe query construction
│   │   └── Schemas/
│   │       ├── RunSchema.swift
│   │       ├── ModelSchema.swift
│   │       ├── IntentSchema.swift
│   │       └── SyncSchema.swift
│   │
│   ├── ContentStore/
│   │   ├── ContentAddressedStore.swift # SHA-256 addressed blobs
│   │   ├── BlobStore.swift             # Raw artifact storage
│   │   ├── LogStore.swift              # Compressed log segments
│   │   ├── MetricStore.swift           # Parquet-based metrics
│   │   └── Deduplicator.swift          # Cross-artifact dedup
│   │
│   └── CachePolicy/
│       ├── RetentionPolicy.swift       # Time/size-based retention
│       ├── EvictionStrategy.swift      # LRU with pinning support
│       └── StorageQuota.swift          # Per-category limits
│
├── Networking/
│   ├── APIClient/
│   │   ├── GRPCClient.swift            # Control plane RPC
│   │   ├── HTTPClient.swift            # Artifact transfers
│   │   ├── WebSocketClient.swift       # Real-time streams
│   │   └── SignedURLGenerator.swift    # Pre-signed upload URLs
│   │
│   └── Protocols/
│       ├── ControlService.proto        # gRPC service definitions
│       └── StreamService.proto
│
├── MLExecution/
│   ├── ExecutionCoordinator.swift      # Route to local/remote
│   ├── LocalExecutor/
│   │   ├── CoreMLRunner.swift          # Production inference
│   │   ├── MLXRunner.swift             # Experimental (Apple Silicon)
│   │   └── ModelLoader.swift           # Lazy model loading
│   │
│   └── RemoteExecutor/
│       ├── KubernetesClient.swift      # K8s job submission
│       ├── CloudRunnerClient.swift     # Managed runner interface
│       └── ExecutionMonitor.swift      # Status polling/streaming
│
└── Observability/
    ├── StructuredLogger.swift          # OSLog + file output
    ├── MetricsCollector.swift          # Internal metrics
    ├── TracingContext.swift            # Distributed tracing spans
    └── DiagnosticBundle.swift          # Debug export
```

### 2.3 UI Module Architecture

```
MacML.app/
├── App/
│   ├── MacMLApp.swift            # @main entry
│   ├── AppDelegate.swift               # AppKit lifecycle hooks
│   └── SceneDelegate.swift             # Window management
│
├── Services/
│   ├── AgentConnection.swift           # XPC client wrapper
│   ├── DataProvider.swift              # Reactive data layer
│   └── NavigationCoordinator.swift     # Deep linking, routing
│
├── Features/
│   ├── Runs/
│   │   ├── RunListView.swift
│   │   ├── RunDetailView.swift
│   │   ├── RunViewModel.swift
│   │   └── RunFilters.swift
│   │
│   ├── Models/
│   │   ├── ModelRegistryView.swift
│   │   ├── ModelDetailView.swift
│   │   ├── ModelCompareView.swift
│   │   └── ModelViewModel.swift
│   │
│   ├── Pipelines/
│   │   ├── PipelineEditorView.swift
│   │   ├── PipelineCanvasView.swift    # DAG visualization
│   │   ├── NodeEditorView.swift
│   │   └── PipelineViewModel.swift
│   │
│   ├── Metrics/
│   │   ├── MetricDashboardView.swift
│   │   ├── ChartComponents/
│   │   │   ├── TimeSeriesChart.swift   # Swift Charts
│   │   │   ├── ScatterPlot.swift
│   │   │   └── ConfusionMatrix.swift
│   │   └── MetricViewModel.swift
│   │
│   ├── Logs/
│   │   ├── LogViewerView.swift
│   │   ├── LogStreamView.swift         # Virtualized list
│   │   ├── LogSearchView.swift
│   │   └── LogViewModel.swift
│   │
│   └── Sync/
│       ├── SyncStatusView.swift
│       ├── ConflictResolutionView.swift
│       └── SyncViewModel.swift
│
├── Components/
│   ├── VirtualizedList.swift           # Large dataset rendering
│   ├── AsyncImage.swift                # Cached image loading
│   ├── SearchField.swift
│   └── StatusIndicator.swift
│
└── Utilities/
    ├── Formatters.swift
    ├── KeyboardShortcuts.swift
    └── Accessibility.swift
```

---

## 3. Data Flow: Offline → Reconnect Scenarios

### 3.1 Offline Operation Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     OFFLINE OPERATION FLOW                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  User Action                                                            │
│       │                                                                 │
│       ▼                                                                 │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  1. UI Process receives user intent                              │   │
│  │     Example: "Start new training run with config X"              │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│       │                                                                 │
│       │ XPC call: submitIntent(RunIntent)                              │
│       ▼                                                                 │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  2. Agent validates and persists intent                          │   │
│  │                                                                   │   │
│  │  Intent {                                                         │   │
│  │    id: UUID (client-generated, idempotency key)                  │   │
│  │    type: .startRun                                                │   │
│  │    payload: RunConfig                                             │   │
│  │    createdAt: timestamp                                           │   │
│  │    status: .pending                                               │   │
│  │    retryCount: 0                                                  │   │
│  │  }                                                                │   │
│  │                                                                   │   │
│  │  → SQLite INSERT (WAL mode, durable)                             │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│       │                                                                 │
│       ▼                                                                 │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  3. Local state machine creates optimistic state                 │   │
│  │                                                                   │   │
│  │  Run {                                                            │   │
│  │    id: UUID (matches intent.id)                                  │   │
│  │    state: .pendingSync                                            │   │
│  │    config: RunConfig                                              │   │
│  │    syncVector: LocalClock(1)                                      │   │
│  │  }                                                                │   │
│  │                                                                   │   │
│  │  → UI immediately shows run in "Pending Sync" state              │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│       │                                                                 │
│       ▼                                                                 │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  4. Network monitor detects offline status                       │   │
│  │                                                                   │   │
│  │  NetworkState.offline → Intent remains in queue                  │   │
│  │  UI shows: "Offline - Changes will sync when connected"          │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ════════════════════════════════════════════════════════════════════  │
│                        OFFLINE PERIOD                                   │
│  ════════════════════════════════════════════════════════════════════  │
│                                                                         │
│  • User can browse all cached runs, models, metrics                    │
│  • User can queue additional intents (all persisted locally)           │
│  • Local ML inference continues working (Core ML / MLX)                │
│  • Logs/metrics from local runs stored in content-addressed store      │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 3.2 Reconnection and Sync Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     RECONNECTION SYNC FLOW                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  Network Restored                                                       │
│       │                                                                 │
│       ▼                                                                 │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  1. NetworkMonitor detects connectivity                          │   │
│  │                                                                   │   │
│  │  → Triggers SyncCoordinator.startSync()                          │   │
│  │  → UI updates: "Syncing..."                                       │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│       │                                                                 │
│       ▼                                                                 │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  2. Phase 1: Pull remote changes (read-only, safe)               │   │
│  │                                                                   │   │
│  │  GET /sync/changes?since={lastSyncVector}                        │   │
│  │                                                                   │   │
│  │  Response: [                                                      │   │
│  │    { entity: Run, id: X, version: 5, data: {...} },              │   │
│  │    { entity: Model, id: Y, version: 3, data: {...} },            │   │
│  │    ...                                                            │   │
│  │  ]                                                                │   │
│  │                                                                   │   │
│  │  → Apply to local SQLite in transaction                          │   │
│  │  → Update local sync vectors                                      │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│       │                                                                 │
│       ▼                                                                 │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  3. Phase 2: Conflict Detection                                  │   │
│  │                                                                   │   │
│  │  For each pending local change:                                   │   │
│  │    - Compare local version with remote version                    │   │
│  │    - If remote changed same entity → CONFLICT                    │   │
│  │    - If no remote change → safe to push                          │   │
│  │                                                                   │   │
│  │  Conflict Resolution Strategies:                                  │   │
│  │  ┌─────────────────────────────────────────────────────────┐    │   │
│  │  │ Entity Type    │ Strategy                               │    │   │
│  │  ├─────────────────────────────────────────────────────────┤    │   │
│  │  │ Run config     │ Last-Write-Wins (timestamp)            │    │   │
│  │  │ Run state      │ Server authoritative (running > local) │    │   │
│  │  │ Model metadata │ Merge (non-conflicting fields)         │    │   │
│  │  │ Model version  │ Fork (create new version)              │    │   │
│  │  │ Pipeline def   │ User prompt (show diff)                │    │   │
│  │  └─────────────────────────────────────────────────────────┘    │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│       │                                                                 │
│       ├──────────────────────────────────────────┐                     │
│       ▼                                          ▼                     │
│  ┌─────────────────────┐                  ┌─────────────────────┐     │
│  │ No Conflicts        │                  │ Conflicts Detected   │     │
│  │                     │                  │                      │     │
│  │ → Proceed to push   │                  │ → Pause sync         │     │
│  └─────────────────────┘                  │ → Notify UI          │     │
│       │                                   │ → Show resolution UI │     │
│       │                                   └──────────┬────────────┘     │
│       │                                              │                  │
│       │                              User resolves   │                  │
│       │                              conflicts       │                  │
│       │◄─────────────────────────────────────────────┘                  │
│       ▼                                                                 │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  4. Phase 3: Push local intents                                  │   │
│  │                                                                   │   │
│  │  For each intent in queue (FIFO order):                          │   │
│  │                                                                   │   │
│  │  POST /intents                                                    │   │
│  │  {                                                                │   │
│  │    idempotencyKey: intent.id,    // Server deduplicates          │   │
│  │    type: intent.type,                                             │   │
│  │    payload: intent.payload                                        │   │
│  │  }                                                                │   │
│  │                                                                   │   │
│  │  Response handling:                                               │   │
│  │  - 200/201: Mark intent complete, update local state             │   │
│  │  - 409 Conflict: Apply conflict resolution                       │   │
│  │  - 4xx Client Error: Mark intent failed, notify user             │   │
│  │  - 5xx Server Error: Retry with exponential backoff              │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│       │                                                                 │
│       ▼                                                                 │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  5. Phase 4: Artifact sync                                       │   │
│  │                                                                   │   │
│  │  Pull missing artifacts (lazy, on-demand with prefetch hints):   │   │
│  │  - Model weights for recently viewed models                      │   │
│  │  - Logs for active/recent runs                                   │   │
│  │  - Metrics for dashboard views                                   │   │
│  │                                                                   │   │
│  │  Push local artifacts:                                            │   │
│  │  - Artifacts from local runs                                      │   │
│  │  - Model files staged for deployment                             │   │
│  │                                                                   │   │
│  │  Transfer characteristics:                                        │   │
│  │  - Resumable (chunk-based with server-side assembly)             │   │
│  │  - Parallel (configurable concurrency, default 4)                │   │
│  │  - Verified (SHA-256 integrity check)                            │   │
│  │  - Compressed (zstd for logs, passthrough for models)            │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│       │                                                                 │
│       ▼                                                                 │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  6. Sync Complete                                                │   │
│  │                                                                   │   │
│  │  → Update lastSyncVector                                         │   │
│  │  → Clear processed intents from queue                            │   │
│  │  → Publish SyncComplete event to UI                              │   │
│  │  → UI shows: "Synced" with timestamp                             │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 3.3 Conflict Resolution Detail

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    CONFLICT RESOLUTION MATRIX                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌──────────────┬────────────────┬─────────────────────────────────┐   │
│  │ Conflict Type│ Auto-Resolve?  │ Strategy                        │   │
│  ├──────────────┼────────────────┼─────────────────────────────────┤   │
│  │              │                │                                  │   │
│  │ Run Created  │ Yes            │ Both versions kept (no conflict)│   │
│  │ Offline      │                │ Local run gets unique ID        │   │
│  │              │                │                                  │   │
│  ├──────────────┼────────────────┼─────────────────────────────────┤   │
│  │              │                │                                  │   │
│  │ Run State    │ Yes            │ Server authoritative            │   │
│  │ Mismatch     │                │ Remote "completed" > local      │   │
│  │              │                │ "running"                        │   │
│  │              │                │                                  │   │
│  ├──────────────┼────────────────┼─────────────────────────────────┤   │
│  │              │                │                                  │   │
│  │ Run Config   │ Conditional    │ If run not started: LWW         │   │
│  │ Edit         │                │ If run started: reject local    │   │
│  │              │                │                                  │   │
│  ├──────────────┼────────────────┼─────────────────────────────────┤   │
│  │              │                │                                  │   │
│  │ Model Meta   │ Yes            │ Field-level merge               │   │
│  │ Edit         │                │ (description, tags, etc.)       │   │
│  │              │                │                                  │   │
│  ├──────────────┼────────────────┼─────────────────────────────────┤   │
│  │              │                │                                  │   │
│  │ Model Stage  │ No             │ Prompt user                     │   │
│  │ Conflict     │                │ "Model X was deployed by User Y │   │
│  │              │                │  while you were offline"        │   │
│  │              │                │                                  │   │
│  ├──────────────┼────────────────┼─────────────────────────────────┤   │
│  │              │                │                                  │   │
│  │ Pipeline     │ No             │ Show 3-way diff                 │   │
│  │ Definition   │                │ User selects resolution         │   │
│  │              │                │                                  │   │
│  ├──────────────┼────────────────┼─────────────────────────────────┤   │
│  │              │                │                                  │   │
│  │ Delete vs    │ Yes            │ Delete wins (tombstone)         │   │
│  │ Edit         │                │ Log conflict for audit          │   │
│  │              │                │                                  │   │
│  └──────────────┴────────────────┴─────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Technology Stack with Justifications

### 4.1 Core Technologies

| Layer | Technology | Justification |
|-------|-----------|---------------|
| **UI Framework** | SwiftUI + AppKit | Native macOS performance, accessibility built-in, seamless Apple Silicon optimization. AppKit for complex views (virtualized lists, custom drawing). |
| **IPC** | XPC Services | Apple's recommended IPC for macOS. Mach port-based, zero-copy for large payloads, automatic connection management, crash isolation. |
| **Database** | SQLite (WAL mode) | Single-file deployment, ACID transactions, excellent read performance, WAL enables concurrent reads during writes. Well-tested with billions of deployments. |
| **Async Runtime** | Swift Concurrency | Native async/await, structured concurrency with TaskGroups, Actors for thread-safe state, seamless integration with system frameworks. |
| **Networking (Control)** | gRPC-Swift | HTTP/2 multiplexing, bidirectional streaming, strong typing from protobuf, efficient binary protocol. |
| **Networking (Artifacts)** | URLSession | Native HTTP/2 support, automatic retry, background transfers, system-level connection pooling. |
| **Serialization** | Protobuf + Codable | Protobuf for wire format (compact, versioned). Codable for local persistence and XPC (native Swift ergonomics). |
| **Compression** | zstd (via Apple's Compression) | Best compression ratio for logs/text, fast decompression, dictionary support for similar content. |
| **Content Hashing** | SHA-256 (CryptoKit) | Hardware-accelerated on Apple Silicon, standard content addressing, collision resistant. |
| **Secrets** | Keychain Services | OS-managed credential storage, Secure Enclave integration, automatic iCloud sync (optional). |
| **Logging** | OSLog (os_log) | Structured logging, efficient binary format, system-wide aggregation, privacy redaction. |
| **ML Inference** | Core ML | ANE/GPU acceleration, model optimization, on-device privacy. |
| **ML Experimentation** | MLX | Apple Silicon native, NumPy-like API, unified memory for large models. |
| **Metrics Storage** | Apache Parquet | Columnar format, excellent compression for time-series, efficient range queries. |

### 4.2 Third-Party Dependencies (Minimal)

| Dependency | Purpose | Justification |
|------------|---------|---------------|
| **grpc-swift** | gRPC client/server | Official Apple-supported implementation, NIO-based. |
| **swift-protobuf** | Protobuf codegen | Required for gRPC, Google-maintained. |
| **swift-argument-parser** | CLI tools | Apple-maintained, for agent CLI interface. |
| **swift-collections** | Data structures | Deque, OrderedSet for queues and caches. |

### 4.3 Rejected Alternatives

| Technology | Reason for Rejection |
|------------|---------------------|
| **Electron** | Memory overhead (200MB+ baseline), no native performance, battery drain. |
| **Realm/Core Data** | Realm: third-party dependency, sync lock-in. Core Data: complex for this schema, weaker migration story. |
| **WebSockets only** | Missing HTTP/2 multiplexing, no built-in streaming semantics. Used alongside gRPC for specific use cases. |
| **LevelDB/RocksDB** | Key-value stores lack relational queries needed for run/model filtering. SQLite covers both. |
| **REST-only** | No streaming, inefficient for real-time updates, more round trips. |

---

## 5. Performance-Critical Design Decisions and Tradeoffs

### 5.1 UI Responsiveness

```
┌─────────────────────────────────────────────────────────────────────────┐
│              UI RESPONSIVENESS ARCHITECTURE                              │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  PRINCIPLE: Main thread does ONLY rendering and user input              │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  Decision: All data flows through XPC, never direct DB access    │   │
│  │                                                                   │   │
│  │  Tradeoff:                                                        │   │
│  │  + UI process never blocks on I/O                                │   │
│  │  + Crash isolation (agent crash doesn't kill UI)                 │   │
│  │  + Memory isolation (agent can use more RAM)                     │   │
│  │  - Slight latency for simple queries (~1-5ms XPC overhead)       │   │
│  │  - More complex data flow                                        │   │
│  │                                                                   │   │
│  │  Mitigation: Aggressive UI-side caching with invalidation        │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  Decision: Virtualized lists for all large datasets              │   │
│  │                                                                   │   │
│  │  Implementation:                                                  │   │
│  │  - Custom NSCollectionView wrapper for 100k+ item lists         │   │
│  │  - SwiftUI LazyVStack for smaller lists (<1000 items)           │   │
│  │  - Windowed data loading: fetch visible + 2 pages buffer        │   │
│  │                                                                   │   │
│  │  Tradeoff:                                                        │   │
│  │  + Constant memory regardless of dataset size                    │   │
│  │  + Instant scroll with prefetch                                  │   │
│  │  - More complex view implementation                              │   │
│  │  - Scroll position bookkeeping                                   │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  Decision: AsyncStream for live log/metric updates               │   │
│  │                                                                   │   │
│  │  Implementation:                                                  │   │
│  │  - Agent publishes updates via XPC AsyncStream                   │   │
│  │  - UI subscribes with automatic backpressure                     │   │
│  │  - Batch UI updates at 60fps max (coalesce within frame)        │   │
│  │                                                                   │   │
│  │  Tradeoff:                                                        │   │
│  │  + Real-time updates without polling                             │   │
│  │  + Natural backpressure prevents UI flood                        │   │
│  │  - Stream management complexity                                  │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 5.2 Storage Performance

```
┌─────────────────────────────────────────────────────────────────────────┐
│                   STORAGE PERFORMANCE DECISIONS                          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  Decision: SQLite WAL mode with connection pooling               │   │
│  │                                                                   │   │
│  │  Configuration:                                                   │   │
│  │  - PRAGMA journal_mode = WAL                                     │   │
│  │  - PRAGMA synchronous = NORMAL (not FULL)                        │   │
│  │  - PRAGMA cache_size = -64000 (64MB)                             │   │
│  │  - Connection pool: 1 writer, 4 readers                          │   │
│  │                                                                   │   │
│  │  Tradeoff:                                                        │   │
│  │  + Concurrent reads during writes                                │   │
│  │  + 10-100x write performance vs rollback journal                 │   │
│  │  - Slightly more disk usage (WAL file)                           │   │
│  │  - Checkpoint management needed                                  │   │
│  │                                                                   │   │
│  │  Benchmark: 50k run inserts/sec, 200k queries/sec               │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  Decision: Content-addressed storage with lazy deduplication     │   │
│  │                                                                   │   │
│  │  Implementation:                                                  │   │
│  │  - Files stored as: {store}/{hash[0:2]}/{hash[2:4]}/{hash}      │   │
│  │  - Hash computed on write, verified on read                      │   │
│  │  - Dedup check: O(1) hash lookup before write                   │   │
│  │  - Reference counting for garbage collection                     │   │
│  │                                                                   │   │
│  │  Tradeoff:                                                        │   │
│  │  + Automatic deduplication across runs/models                    │   │
│  │  + Integrity verification built-in                               │   │
│  │  + Simple backup (just copy directory)                           │   │
│  │  - Hash computation overhead (mitigated by streaming hash)       │   │
│  │  - Rename requires copy (content-addressed = immutable)          │   │
│  │                                                                   │   │
│  │  Space savings: 30-60% typical for ML artifacts                  │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  Decision: Parquet for time-series metrics                       │   │
│  │                                                                   │   │
│  │  Implementation:                                                  │   │
│  │  - One parquet file per run per metric type                      │   │
│  │  - Columnar storage with dictionary encoding                     │   │
│  │  - Append-only during run, compact on completion                 │   │
│  │                                                                   │   │
│  │  Tradeoff:                                                        │   │
│  │  + 10-50x compression vs CSV/JSON                                │   │
│  │  + Fast columnar scans for time ranges                           │   │
│  │  + Schema evolution support                                      │   │
│  │  - Write amplification for appends (mitigated by buffering)      │   │
│  │  - Binary format (not human-readable)                            │   │
│  │                                                                   │   │
│  │  Query: 1M metric points in <100ms                               │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 5.3 Network Performance

```
┌─────────────────────────────────────────────────────────────────────────┐
│                   NETWORK PERFORMANCE DECISIONS                          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  Decision: Chunked resumable uploads with parallel transfers     │   │
│  │                                                                   │   │
│  │  Implementation:                                                  │   │
│  │  - Chunk size: 8MB (balance between overhead and resumability)  │   │
│  │  - Parallel chunks: 4 concurrent (configurable)                  │   │
│  │  - Resume: Server tracks received chunks, client queries gaps   │   │
│  │  - Assembly: Server-side assembly with final integrity check    │   │
│  │                                                                   │   │
│  │  Tradeoff:                                                        │   │
│  │  + Network interruption loses at most 8MB progress              │   │
│  │  + 4x throughput on high-latency connections                    │   │
│  │  + Server can receive chunks out of order                       │   │
│  │  - More server complexity                                        │   │
│  │  - Chunk tracking overhead (~100 bytes/chunk)                   │   │
│  │                                                                   │   │
│  │  Benchmark: 10GB model upload in 5min on 300Mbps connection     │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  Decision: gRPC streaming for logs and metrics                   │   │
│  │                                                                   │   │
│  │  Implementation:                                                  │   │
│  │  - Bidirectional stream per active run                           │   │
│  │  - Client sends heartbeat, server sends log chunks              │   │
│  │  - Batched: max 100 log lines or 100ms, whichever first         │   │
│  │  - Compression: per-message gzip for text-heavy payloads        │   │
│  │                                                                   │   │
│  │  Tradeoff:                                                        │   │
│  │  + Single connection for all real-time data                     │   │
│  │  + Flow control built into HTTP/2                               │   │
│  │  + Efficient binary framing                                      │   │
│  │  - gRPC complexity vs simple WebSocket                          │   │
│  │  - Requires HTTP/2 (not an issue for modern infra)              │   │
│  │                                                                   │   │
│  │  Latency: <50ms log line to UI (P99)                            │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  Decision: Adaptive bandwidth control with fair queuing          │   │
│  │                                                                   │   │
│  │  Implementation:                                                  │   │
│  │  - Monitor: Sample throughput every 5 seconds                    │   │
│  │  - Adapt: Reduce concurrency on congestion detection            │   │
│  │  - Priority: Control plane > active run data > backfill         │   │
│  │  - Fair: Round-robin across pending transfers                   │   │
│  │                                                                   │   │
│  │  Tradeoff:                                                        │   │
│  │  + Doesn't saturate user's connection                           │   │
│  │  + Important transfers complete first                            │   │
│  │  + Graceful degradation on poor networks                        │   │
│  │  - Suboptimal throughput on idle networks                       │   │
│  │  - Complexity of priority management                            │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 5.4 Memory Management

```
┌─────────────────────────────────────────────────────────────────────────┐
│                   MEMORY MANAGEMENT DECISIONS                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  Decision: Strict memory budgets per component                   │   │
│  │                                                                   │   │
│  │  Budgets:                                                         │   │
│  │  - UI Process: 200-500MB (view cache, recent data)              │   │
│  │  - Agent Daemon: 500MB-2GB (configurable, default 1GB)          │   │
│  │  - ML Runner: Dynamic (model size + 20% overhead)               │   │
│  │                                                                   │   │
│  │  Enforcement:                                                     │   │
│  │  - LRU cache eviction when approaching budget                   │   │
│  │  - Memory pressure notifications from OS                        │   │
│  │  - Automatic checkpoint and trim on background                  │   │
│  │                                                                   │   │
│  │  Tradeoff:                                                        │   │
│  │  + Predictable resource usage                                    │   │
│  │  + Good citizen on shared machines                               │   │
│  │  + Prevents OOM crashes                                          │   │
│  │  - May evict useful cache under pressure                        │   │
│  │  - Requires careful cache sizing                                 │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  Decision: Streaming processing for large artifacts              │   │
│  │                                                                   │   │
│  │  Implementation:                                                  │   │
│  │  - Never load full artifact into memory                         │   │
│  │  - Stream hash: compute while reading/writing                   │   │
│  │  - Stream compress: zstd streaming API                          │   │
│  │  - Stream transfer: chunked encoding                            │   │
│  │                                                                   │   │
│  │  Tradeoff:                                                        │   │
│  │  + 100GB model file uses <100MB RAM                             │   │
│  │  + No practical artifact size limit                             │   │
│  │  + Progress tracking built into stream                          │   │
│  │  - Slightly more I/O (multiple passes for some operations)      │   │
│  │  - Can't seek randomly in compressed streams                    │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  Decision: Lazy model loading for ML execution                   │   │
│  │                                                                   │   │
│  │  Implementation:                                                  │   │
│  │  - Models loaded on first inference request                     │   │
│  │  - Unified memory (Apple Silicon): model stays in RAM           │   │
│  │  - LRU eviction of loaded models under memory pressure          │   │
│  │  - Preload hints from UI for anticipated inference              │   │
│  │                                                                   │   │
│  │  Tradeoff:                                                        │   │
│  │  + Only pay memory cost for active models                       │   │
│  │  + Can run larger models than RAM (with swapping penalty)       │   │
│  │  - First inference has loading latency                          │   │
│  │  - Memory spikes during load                                     │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 5.5 Sync Performance

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     SYNC PERFORMANCE DECISIONS                           │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  Decision: Incremental sync with vector clocks                   │   │
│  │                                                                   │   │
│  │  Implementation:                                                  │   │
│  │  - Each entity has monotonic version number                      │   │
│  │  - Client tracks lastSyncVersion per entity type                │   │
│  │  - Server returns only changes since client version             │   │
│  │  - Batch sync: max 1000 entities per request                    │   │
│  │                                                                   │   │
│  │  Tradeoff:                                                        │   │
│  │  + Minimal data transfer after initial sync                     │   │
│  │  + Fast reconnection (seconds, not minutes)                     │   │
│  │  + Server can optimize change tracking with indexes             │   │
│  │  - Requires server-side change tracking                         │   │
│  │  - Initial sync still transfers full dataset                    │   │
│  │                                                                   │   │
│  │  Benchmark: 10k entity delta sync in <2 seconds                 │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  Decision: Background sync with priority scheduling              │   │
│  │                                                                   │   │
│  │  Priority order:                                                  │   │
│  │  1. Intent queue (user actions waiting to sync)                 │   │
│  │  2. Active view data (what user is looking at)                  │   │
│  │  3. Recent runs (last 24 hours)                                 │   │
│  │  4. Historical backfill (oldest first)                          │   │
│  │                                                                   │   │
│  │  Tradeoff:                                                        │   │
│  │  + User actions sync immediately                                 │   │
│  │  + Current view always fresh                                     │   │
│  │  + Background work doesn't block interaction                    │   │
│  │  - Old data may be stale until backfill completes               │   │
│  │  - Priority management complexity                                │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 6. Security Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      SECURITY ARCHITECTURE                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  Credential Management                                            │   │
│  │                                                                   │   │
│  │  Storage: macOS Keychain (kSecClassGenericPassword)              │   │
│  │  - API tokens                                                     │   │
│  │  - OAuth refresh tokens                                          │   │
│  │  - SSH keys for Git operations                                   │   │
│  │                                                                   │   │
│  │  Access: Keychain Services API with app-specific access group    │   │
│  │  - UI and Agent share keychain access group                      │   │
│  │  - Biometric unlock optional (Touch ID)                          │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  Application Security                                             │   │
│  │                                                                   │   │
│  │  Hardened Runtime:                                                │   │
│  │  - Code signing required                                          │   │
│  │  - Library validation                                             │   │
│  │  - No unsigned executable memory                                 │   │
│  │                                                                   │   │
│  │  Sandboxing:                                                      │   │
│  │  - UI Process: Strict sandbox, network + user files only        │   │
│  │  - Agent: Network, ~/Library/Application Support, temp          │   │
│  │  - ML Runner: No network, specific model directories only       │   │
│  │                                                                   │   │
│  │  Notarization: Required for distribution                         │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  Offline RBAC                                                     │   │
│  │                                                                   │   │
│  │  Implementation:                                                  │   │
│  │  - Permissions cached locally with TTL (default: 1 hour)        │   │
│  │  - Permission check: local cache first, refresh on network      │   │
│  │  - Expired cache: allow read-only, block mutations              │   │
│  │  - Audit log: all permission checks logged locally              │   │
│  │                                                                   │   │
│  │  Cache structure:                                                 │   │
│  │  {                                                                │   │
│  │    user_id: "...",                                               │   │
│  │    roles: ["admin", "ml_engineer"],                              │   │
│  │    permissions: ["run:create", "model:deploy", ...],             │   │
│  │    fetched_at: timestamp,                                         │   │
│  │    expires_at: timestamp                                          │   │
│  │  }                                                                │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  Network Security                                                 │   │
│  │                                                                   │   │
│  │  - TLS 1.3 required for all connections                         │   │
│  │  - Certificate pinning for API endpoints (optional config)      │   │
│  │  - Mutual TLS for enterprise deployments                        │   │
│  │  - No sensitive data in URLs (use POST bodies or headers)       │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 7. Observability Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     OBSERVABILITY ARCHITECTURE                           │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  Structured Logging                                               │   │
│  │                                                                   │   │
│  │  Format: OSLog with structured metadata                          │   │
│  │                                                                   │   │
│  │  Categories:                                                      │   │
│  │  - com.macml.ui          (UI events)                       │   │
│  │  - com.macml.agent       (Agent operations)                │   │
│  │  - com.macml.sync        (Sync activity)                   │   │
│  │  - com.macml.network     (Network operations)              │   │
│  │  - com.macml.storage     (Storage operations)              │   │
│  │  - com.macml.ml          (ML execution)                    │   │
│  │                                                                   │   │
│  │  Levels: debug, info, warning, error, fault                      │   │
│  │  Privacy: .private for PII, .public for safe data               │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  Distributed Tracing                                              │   │
│  │                                                                   │   │
│  │  Trace propagation:                                               │   │
│  │  UI Action → XPC Call → Agent Operation → Network Request        │   │
│  │      │           │            │                │                 │   │
│  │   trace_id   trace_id     trace_id         trace_id              │   │
│  │   span_id    span_id      span_id          span_id               │   │
│  │                                                                   │   │
│  │  Implementation:                                                  │   │
│  │  - W3C Trace Context format                                      │   │
│  │  - Propagate via XPC and HTTP headers                           │   │
│  │  - Local trace storage in SQLite (last 24h)                     │   │
│  │  - Export to backend for aggregation                            │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  Internal Metrics                                                 │   │
│  │                                                                   │   │
│  │  Collected metrics:                                               │   │
│  │  - sync_duration_ms (histogram)                                  │   │
│  │  - intent_queue_depth (gauge)                                    │   │
│  │  - artifact_transfer_bytes (counter)                             │   │
│  │  - cache_hit_ratio (gauge)                                       │   │
│  │  - db_query_duration_ms (histogram)                              │   │
│  │  - memory_usage_bytes (gauge)                                    │   │
│  │                                                                   │   │
│  │  Export: Prometheus format (optional scrape endpoint)            │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  Diagnostic Bundle                                                │   │
│  │                                                                   │   │
│  │  Contents (user-triggered export):                               │   │
│  │  - Recent logs (last 1 hour, redacted)                          │   │
│  │  - Sync state snapshot                                           │   │
│  │  - Intent queue contents                                         │   │
│  │  - Network reachability history                                  │   │
│  │  - System info (OS version, hardware)                           │   │
│  │  - Performance metrics summary                                   │   │
│  │                                                                   │   │
│  │  Format: ZIP archive, no credentials/PII                        │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 8. Directory Structure

```
MacML/
├── MacML.xcworkspace           # Xcode workspace
├── MacML/                       # UI App target
│   ├── App/
│   ├── Features/
│   ├── Services/
│   ├── Components/
│   └── Resources/
│
├── MacMLAgent/                  # Agent daemon target
│   ├── Core/
│   ├── ControlPlane/
│   ├── DataPlane/
│   ├── Storage/
│   ├── Networking/
│   ├── MLExecution/
│   └── Observability/
│
├── MacMLMLRunner/               # ML runner target
│   ├── CoreMLRunner/
│   └── MLXRunner/
│
├── MacMLKit/                    # Shared framework
│   ├── Models/                        # Shared data models
│   ├── Protocols/                     # XPC protocols
│   ├── Utilities/                     # Common utilities
│   └── Constants/
│
├── Protos/                            # Protocol buffer definitions
│   ├── control.proto
│   ├── stream.proto
│   └── models.proto
│
├── Scripts/
│   ├── generate-protos.sh
│   ├── setup-dev.sh
│   └── notarize.sh
│
├── Tests/
│   ├── MacMLTests/
│   ├── MacMLAgentTests/
│   └── IntegrationTests/
│
└── Documentation/
    ├── ARCHITECTURE.md               # This document
    ├── API.md
    └── DEVELOPMENT.md
```

---

## 9. Implementation Phases

### Phase 1: Foundation
- XPC infrastructure and protocol definitions
- SQLite storage layer with WAL
- Basic UI shell with navigation
- Agent daemon lifecycle

### Phase 2: Offline Core
- Intent queue and idempotency store
- State machines for runs and models
- Content-addressed blob storage
- Local-only run/model CRUD

### Phase 3: Sync Engine
- Incremental sync coordinator
- Conflict detection and resolution
- Network monitoring and retry logic
- Sync status UI

### Phase 4: Data Plane
- Resumable artifact transfers
- Log streaming infrastructure
- Metric ingestion and storage
- Backpressure control

### Phase 5: ML Execution
- Core ML runner integration
- MLX experimental support
- Remote execution client
- Model lifecycle management

### Phase 6: Polish
- Performance optimization
- Security hardening
- Observability integration
- Documentation

---

## 10. Key Invariants

1. **UI never blocks on I/O** - All data access through async XPC
2. **Intents are durable** - User action persists before acknowledgment
3. **Sync is resumable** - Any interruption can be recovered
4. **Content is verified** - All artifacts have integrity checks
5. **Credentials never leave Keychain** - Tokens used, never exposed
6. **Memory is bounded** - Predictable resource usage under all workloads
7. **Offline is first-class** - Full functionality without network

---

*Document Version: 1.0*
*Architecture for: MacML MLOps Platform*
