import SwiftUI

/// Palette from the illustrated Watch screens, shared by both apps.
enum LensTheme {
    static let background = Color(red: 24 / 255, green: 17 / 255, blue: 34 / 255)
    static let lavender = Color(red: 214 / 255, green: 179 / 255, blue: 244 / 255)
    static let muted = Color(red: 63 / 255, green: 43 / 255, blue: 80 / 255)
    static let secondary = Color(red: 212 / 255, green: 192 / 255, blue: 224 / 255)
    static let text = Color(red: 253 / 255, green: 247 / 255, blue: 255 / 255)
}

/// A quieter companion palette with neutral surfaces and selective colour accents.
enum PhonePalette {
    static let background = Color(red: 7 / 255, green: 6 / 255, blue: 11 / 255)
    static let surface = Color(red: 34 / 255, green: 30 / 255, blue: 43 / 255)
    static let secondaryButton = Color(red: 49 / 255, green: 40 / 255, blue: 64 / 255)
    static let accent = Color(red: 207 / 255, green: 180 / 255, blue: 244 / 255)
    static let secondary = Color(red: 181 / 255, green: 172 / 255, blue: 194 / 255)
    static let text = Color(red: 246 / 255, green: 242 / 255, blue: 250 / 255)
    static let mint = Color(red: 171 / 255, green: 220 / 255, blue: 201 / 255)
    static let separator = Color(red: 62 / 255, green: 55 / 255, blue: 75 / 255)
}

extension View {
    @ViewBuilder
    func lensPhoneSurface() -> some View {
        #if os(iOS)
        self.scrollContentBackground(.hidden)
            .background(PhonePalette.background)
            .toolbarBackground(PhonePalette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        #else
        self
        #endif
    }

    @ViewBuilder
    func lensPhoneRows() -> some View {
        #if os(iOS)
        self.listRowBackground(PhonePalette.surface)
            .listRowSeparatorTint(PhonePalette.separator)
        #else
        self
        #endif
    }
}
