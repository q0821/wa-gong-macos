import Foundation

enum ShortcutBindingResolver {
    static func resolve(
        bindings: [ShortcutBinding],
        matching shortcut: Shortcut,
        sourceDevice: KeyboardDeviceReference?,
        deviceMatchingAvailable: Bool
    ) -> ShortcutBinding? {
        let matchingBindings = bindings.filter { $0.shortcut.conflicts(with: shortcut) }

        if deviceMatchingAvailable, let sourceDevice,
            let deviceBinding = matchingBindings.first(where: { binding in
                guard case .device(let storedDevice) = binding.scope else {
                    return false
                }
                return storedDevice.matches(sourceDevice)
            })
        {
            return deviceBinding
        }

        return matchingBindings.first { binding in
            binding.scope == .allKeyboards
        }
    }
}
