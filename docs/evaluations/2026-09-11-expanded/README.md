# Expanded comparison evidence

`audit.swift` is the bounded comparison harness, not production app code. It imports the current `CatanAI`, `CatanEngine`, and a `FrozenCatanAI` module made from every `Packages/CatanAI/Sources/CatanAI/*.swift` file at commit `0f8a65c`. Compile as a Swift 6 executable in Release on macOS 14+. Both policy modules use the current engine. Run with argument `12` for twelve games per arm.

The temporary package used for this run is `/tmp/catan-expanded-audit-20260911`; its output is retained alongside this file once complete. This path is a local convenience, not a dependency of the application. The plan records the protocol and conclusions.
