import Carbon.HIToolbox
import Foundation

struct HIDKeyboardUsageDescriptor: Equatable, Sendable {
    enum Kind: Sendable {
        case key
        case modifier
    }

    let usage: UInt32
    let kind: Kind
    let suggestedCarbonKeyCode: UInt16?
}

enum HIDKeyboardUsageMapper {
    static func descriptor(for usage: UInt32) -> HIDKeyboardUsageDescriptor? {
        guard (0x04...0xE7).contains(usage) else {
            return nil
        }

        let kind: HIDKeyboardUsageDescriptor.Kind = (0xE0...0xE7).contains(usage) ? .modifier : .key
        return HIDKeyboardUsageDescriptor(
            usage: usage,
            kind: kind,
            suggestedCarbonKeyCode: carbonKeyCodes[usage]
        )
    }

    private static let carbonKeyCodes: [UInt32: UInt16] = [
        0x04: UInt16(kVK_ANSI_A),
        0x05: UInt16(kVK_ANSI_B),
        0x06: UInt16(kVK_ANSI_C),
        0x07: UInt16(kVK_ANSI_D),
        0x08: UInt16(kVK_ANSI_E),
        0x09: UInt16(kVK_ANSI_F),
        0x0A: UInt16(kVK_ANSI_G),
        0x0B: UInt16(kVK_ANSI_H),
        0x0C: UInt16(kVK_ANSI_I),
        0x0D: UInt16(kVK_ANSI_J),
        0x0E: UInt16(kVK_ANSI_K),
        0x0F: UInt16(kVK_ANSI_L),
        0x10: UInt16(kVK_ANSI_M),
        0x11: UInt16(kVK_ANSI_N),
        0x12: UInt16(kVK_ANSI_O),
        0x13: UInt16(kVK_ANSI_P),
        0x14: UInt16(kVK_ANSI_Q),
        0x15: UInt16(kVK_ANSI_R),
        0x16: UInt16(kVK_ANSI_S),
        0x17: UInt16(kVK_ANSI_T),
        0x18: UInt16(kVK_ANSI_U),
        0x19: UInt16(kVK_ANSI_V),
        0x1A: UInt16(kVK_ANSI_W),
        0x1B: UInt16(kVK_ANSI_X),
        0x1C: UInt16(kVK_ANSI_Y),
        0x1D: UInt16(kVK_ANSI_Z),
        0x1E: UInt16(kVK_ANSI_1),
        0x1F: UInt16(kVK_ANSI_2),
        0x20: UInt16(kVK_ANSI_3),
        0x21: UInt16(kVK_ANSI_4),
        0x22: UInt16(kVK_ANSI_5),
        0x23: UInt16(kVK_ANSI_6),
        0x24: UInt16(kVK_ANSI_7),
        0x25: UInt16(kVK_ANSI_8),
        0x26: UInt16(kVK_ANSI_9),
        0x27: UInt16(kVK_ANSI_0),
        0x28: UInt16(kVK_Return),
        0x29: UInt16(kVK_Escape),
        0x2A: UInt16(kVK_Delete),
        0x2B: UInt16(kVK_Tab),
        0x2C: UInt16(kVK_Space),
        0x2D: UInt16(kVK_ANSI_Minus),
        0x2E: UInt16(kVK_ANSI_Equal),
        0x2F: UInt16(kVK_ANSI_LeftBracket),
        0x30: UInt16(kVK_ANSI_RightBracket),
        0x31: UInt16(kVK_ANSI_Backslash),
        0x33: UInt16(kVK_ANSI_Semicolon),
        0x34: UInt16(kVK_ANSI_Quote),
        0x35: UInt16(kVK_ANSI_Grave),
        0x36: UInt16(kVK_ANSI_Comma),
        0x37: UInt16(kVK_ANSI_Period),
        0x38: UInt16(kVK_ANSI_Slash),
        0x3A: UInt16(kVK_F1),
        0x3B: UInt16(kVK_F2),
        0x3C: UInt16(kVK_F3),
        0x3D: UInt16(kVK_F4),
        0x3E: UInt16(kVK_F5),
        0x3F: UInt16(kVK_F6),
        0x40: UInt16(kVK_F7),
        0x41: UInt16(kVK_F8),
        0x42: UInt16(kVK_F9),
        0x43: UInt16(kVK_F10),
        0x44: UInt16(kVK_F11),
        0x45: UInt16(kVK_F12),
        0x49: UInt16(kVK_Home),
        0x4A: UInt16(kVK_PageUp),
        0x4B: UInt16(kVK_ForwardDelete),
        0x4D: UInt16(kVK_End),
        0x4E: UInt16(kVK_PageDown),
        0x4F: UInt16(kVK_RightArrow),
        0x50: UInt16(kVK_LeftArrow),
        0x51: UInt16(kVK_DownArrow),
        0x52: UInt16(kVK_UpArrow),
        0xE0: UInt16(kVK_Control),
        0xE1: UInt16(kVK_Shift),
        0xE2: UInt16(kVK_Option),
        0xE3: UInt16(kVK_Command),
        0xE4: UInt16(kVK_RightControl),
        0xE5: UInt16(kVK_RightShift),
        0xE6: UInt16(kVK_RightOption),
        0xE7: UInt16(kVK_RightCommand),
    ]
}
