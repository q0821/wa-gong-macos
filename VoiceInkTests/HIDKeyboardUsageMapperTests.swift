import Carbon.HIToolbox
import Testing
@testable import VoiceInk

struct HIDKeyboardUsageMapperTests {
    @Test func mapsLettersPunctuationAndNavigationKeys() {
        #expect(HIDKeyboardUsageMapper.descriptor(for: 0x04)?.suggestedCarbonKeyCode == UInt16(kVK_ANSI_A))
        #expect(HIDKeyboardUsageMapper.descriptor(for: 0x36)?.suggestedCarbonKeyCode == UInt16(kVK_ANSI_Comma))
        #expect(HIDKeyboardUsageMapper.descriptor(for: 0x50)?.suggestedCarbonKeyCode == UInt16(kVK_LeftArrow))
    }

    @Test func keepsLeftAndRightModifiersDistinct() {
        let leftOption = HIDKeyboardUsageMapper.descriptor(for: 0xE2)
        let rightOption = HIDKeyboardUsageMapper.descriptor(for: 0xE6)

        #expect(leftOption?.kind == .modifier)
        #expect(rightOption?.kind == .modifier)
        #expect(leftOption?.suggestedCarbonKeyCode == UInt16(kVK_Option))
        #expect(rightOption?.suggestedCarbonKeyCode == UInt16(kVK_RightOption))
        #expect(leftOption != rightOption)
    }

    @Test func ignoresUnsupportedKeyboardUsages() {
        #expect(HIDKeyboardUsageMapper.descriptor(for: 0x03) == nil)
        #expect(HIDKeyboardUsageMapper.descriptor(for: 0xE8) == nil)
    }
}
