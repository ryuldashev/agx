import Foundation
import agtermCore
import os

private let logger = Logger(subsystem: Brand.bundleID, category: "Artifacts")

extension AppActions {
    /// Show (or raise) the Artifacts window — `show_artifacts`, View ▸ Artifacts, the palette row and
    /// `artifact.show`. App-global: the index is not per window.
    func showArtifacts() {
        guard let artifacts else { return }
        ArtifactsWindowController.shared.show(library: artifacts, actions: self)
    }

    /// Attach the index once the scene has a state dir; a failed save is logged, never surfaced modally.
    func attachArtifacts(_ library: ArtifactLibrary) {
        artifacts = library
        library.saveFailed = { error in logger.error("artifacts.json save failed: \(error.localizedDescription)") }
    }
}
