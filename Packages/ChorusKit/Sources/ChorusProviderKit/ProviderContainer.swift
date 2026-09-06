import Foundation

/// Resolves the shared container a provider installs its artifacts into.
///
/// The identifier deliberately does not live in `Provider.json`. macOS derives an
/// app group container from the team identifier in the code signature, so the
/// correct value is a property of *how the bundle was signed* rather than of what
/// the provider downloads. The build writes one `$(CHORUS_APP_GROUP)` value into
/// both the entitlements and `Info.plist`; reading it back here keeps the app, the
/// extension, and the signature in step no matter which team builds them.
public enum ProviderContainer {
    /// `Info.plist` key the build populates from `$(CHORUS_APP_GROUP)`.
    public static let infoDictionaryKey = "ChorusAppGroup"

    /// The app group this bundle is entitled to.
    ///
    /// @param bundle Bundle whose `Info.plist` carries the injected identifier.
    /// @return The app group identifier, always `<team identifier>.<group name>`.
    /// @throws ``ProviderDescriptor/DescriptorError/appGroupUnavailable`` when the
    ///   key is absent, or when it is present but has no team half — which is what
    ///   an unsigned build produces, since `DEVELOPMENT_TEAM` is empty there.
    public static func appGroupIdentifier(in bundle: Bundle = .main) throws -> String {
        guard let identifier = bundle.object(forInfoDictionaryKey: infoDictionaryKey) as? String,
              !identifier.isEmpty,
              !identifier.hasPrefix(".") else {
            throw ProviderDescriptor.DescriptorError.appGroupUnavailable
        }
        return identifier
    }

    /// Root directory beneath which every declared artifact is installed.
    public static func storageDirectory(
        in bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) throws -> URL {
        let identifier = try appGroupIdentifier(in: bundle)
        guard let container = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: identifier
        ) else {
            throw ProviderDescriptor.DescriptorError.appGroupUnavailable
        }
        return container.appendingPathComponent("Artifacts", isDirectory: true)
    }
}
