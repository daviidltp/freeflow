// swift-tools-version: 6.0
import PackageDescription

// Proceso auxiliar que transcribe en local con Parakeet TDT 0.6B v3 (FluidAudio, Apache 2.0).
// Va aparte de la app para no tocar su compilación con swiftc: la app lo lanza una vez y le
// pasa rutas de audio por la entrada estándar.
let package = Package(
    name: "ParakeetHelper",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.18.3"),
    ],
    targets: [
        .executableTarget(
            name: "freeflow-parakeet",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")]
        ),
    ]
)
