//
//  ControlsEditor.swift
//  On-screen touch controls layout editor for nxnative (iOS)
//
import SwiftUI
import UIKit

public struct ControlButtonConfig: Codable, Identifiable, Equatable {
    public var id: String             // e.g. "A", "B", "X", "Y", "ZL", "ZR", "L", "R", "PLUS", "MINUS", "L3", "R3", "STICK", "DPAD"
    public var name: String           // Display label: "A", "B", "X", "Y", "ZL", "ZR", "L", "R", "+", "−", "L3", "R3", "Стик", "D-Pad"
    public var x: CGFloat             // Normalized 0.0 ... 1.0 (relative to screen width)
    public var y: CGFloat             // Normalized 0.0 ... 1.0 (relative to screen height)
    public var scale: CGFloat         // 0.5 ... 2.0 (default 1.0)
    public var opacity: CGFloat       // 0.25 ... 1.0 (default 1.0)
    public var isToggle: Bool         // true = toggle mode, false = hold
    public var isHidden: Bool         // true = deleted/hidden
    public var mapping: String        // Target Switch button code (default is id)
    public var isStick: Bool
    public var isDpad: Bool
    public var baseWidth: CGFloat
    public var baseHeight: CGFloat

    public init(id: String, name: String, x: CGFloat, y: CGFloat, scale: CGFloat = 1.0, opacity: CGFloat = 1.0, isToggle: Bool = false, isHidden: Bool = false, mapping: String? = nil, isStick: Bool = false, isDpad: Bool = false, baseWidth: CGFloat = 54, baseHeight: CGFloat = 54) {
        self.id = id
        self.name = name
        self.x = x
        self.y = y
        self.scale = scale
        self.opacity = opacity
        self.isToggle = isToggle
        self.isHidden = isHidden
        self.mapping = mapping ?? id
        self.isStick = isStick
        self.isDpad = isDpad
        self.baseWidth = baseWidth
        self.baseHeight = baseHeight
    }
}

public final class ControlsLayoutStore {
    public static let key2D = "DmControlsLayout_2D"
    public static let key3D = "DmControlsLayout_3D"
    public static let shared = ControlsLayoutStore()

    public static func defaultLayout(is3D: Bool) -> [ControlButtonConfig] {
        var list: [ControlButtonConfig] = [
            // Left Stick (matching DmGamepad K_STICK_X, K_PAD_Y, K_STICK_R)
            ControlButtonConfig(id: "STICK", name: "", x: 0.087, y: 0.81, scale: 1.0, opacity: 1.0, isStick: true, baseWidth: 154, baseHeight: 154),
            // Face Diamond: A, B, X, Y (matching DmGamepad K_FACE_X, K_PAD_Y, K_FACE_GAP, K_FACE_R)
            ControlButtonConfig(id: "A", name: "A", x: 0.967, y: 0.81, scale: 1.0, opacity: 1.0, baseWidth: 54, baseHeight: 54),
            ControlButtonConfig(id: "B", name: "B", x: 0.913, y: 0.925, scale: 1.0, opacity: 1.0, baseWidth: 54, baseHeight: 54),
            ControlButtonConfig(id: "X", name: "X", x: 0.913, y: 0.693, scale: 1.0, opacity: 1.0, baseWidth: 54, baseHeight: 54),
            ControlButtonConfig(id: "Y", name: "Y", x: 0.860, y: 0.81, scale: 1.0, opacity: 1.0, baseWidth: 54, baseHeight: 54),
            // Shoulders: ZL / L on left, ZR / R on right (matching DmGamepad K_ZL_X, K_ZL_Y, K_L_Y)
            ControlButtonConfig(id: "ZL", name: "ZL", x: 0.047, y: 0.093, scale: 1.0, opacity: 1.0, isToggle: true, baseWidth: 52, baseHeight: 52),
            ControlButtonConfig(id: "L", name: "L", x: 0.047, y: 0.251, scale: 1.0, opacity: 1.0, baseWidth: 48, baseHeight: 48),
            ControlButtonConfig(id: "ZR", name: "ZR", x: 0.953, y: 0.093, scale: 1.0, opacity: 1.0, baseWidth: 52, baseHeight: 52),
            ControlButtonConfig(id: "R", name: "R", x: 0.953, y: 0.251, scale: 1.0, opacity: 1.0, baseWidth: 48, baseHeight: 48),
            // Center pills: + and − (matching DmGamepad K_PILL_DX, K_PILL_Y, K_PILL_W, K_PILL_H)
            ControlButtonConfig(id: "PLUS", name: "+", x: 0.556, y: 0.051, scale: 1.0, opacity: 1.0, baseWidth: 50, baseHeight: 28),
            ControlButtonConfig(id: "MINUS", name: "−", x: 0.444, y: 0.051, scale: 1.0, opacity: 1.0, baseWidth: 50, baseHeight: 28)
        ]
        if is3D {
            // 3D mode adds D-Pad and L3/R3
            list.append(ControlButtonConfig(id: "DPAD", name: "D-Pad", x: 0.248, y: 0.85, scale: 1.0, opacity: 1.0, isDpad: true, baseWidth: 96, baseHeight: 96))
            list.append(ControlButtonConfig(id: "L3", name: "L3", x: 0.110, y: 0.093, scale: 1.0, opacity: 1.0, baseWidth: 34, baseHeight: 34))
            list.append(ControlButtonConfig(id: "R3", name: "R3", x: 0.890, y: 0.093, scale: 1.0, opacity: 1.0, baseWidth: 34, baseHeight: 34))
        }
        return list
    }

    public static func loadLayout(is3D: Bool) -> [ControlButtonConfig] {
        let key = is3D ? key3D : key2D
        if let data = UserDefaults.standard.data(forKey: key),
           let list = try? JSONDecoder().decode([ControlButtonConfig].self, from: data), !list.isEmpty {
            return list
        }
        let fn = is3D ? "controls_3d.json" : "controls_2d.json"
        if let docUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent(fn),
           let data = try? Data(contentsOf: docUrl),
           let list = try? JSONDecoder().decode([ControlButtonConfig].self, from: data), !list.isEmpty {
            return list
        }
        if !is3D, let data = UserDefaults.standard.data(forKey: "DmControlsLayout_v1"),
           let list = try? JSONDecoder().decode([ControlButtonConfig].self, from: data), !list.isEmpty {
            return list
        }
        return defaultLayout(is3D: is3D)
    }

    public static func saveLayout(_ items: [ControlButtonConfig], is3D: Bool) {
        let key = is3D ? key3D : key2D
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: key)
        let fn = is3D ? "controls_3d.json" : "controls_2d.json"
        if let docUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent(fn) {
            try? data.write(to: docUrl)
        }
    }

    public static func resetLayout(is3D: Bool) {
        let key = is3D ? key3D : key2D
        UserDefaults.standard.removeObject(forKey: key)
        let fn = is3D ? "controls_3d.json" : "controls_2d.json"
        if let docUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent(fn) {
            try? FileManager.default.removeItem(at: docUrl)
        }
    }
}

public struct ControlsEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var is3DMode: Bool = false
    @State private var items: [ControlButtonConfig] = []
    @State private var originalItems: [ControlButtonConfig] = []
    @State private var selectedId: String? = nil
    @State private var hasChanges: Bool = false

    // Alerts and Dialogs
    @State private var showExitAlert: Bool = false
    @State private var showBgMenu: Bool = false
    @State private var showAddPicker: Bool = false
    @State private var showToast: String? = nil

    private let availableSwitchButtons = [
        ("A", "Кнопка A"),
        ("B", "Кнопка B"),
        ("X", "Кнопка X"),
        ("Y", "Кнопка Y"),
        ("ZL", "Курок ZL (Левый задний)"),
        ("ZR", "Курок ZR (Правый задний)"),
        ("L", "Бампер L (Левый верхний)"),
        ("R", "Бампер R (Правый верхний)"),
        ("PLUS", "Кнопка + (Start/Menu)"),
        ("MINUS", "Кнопка − (Select)"),
        ("L3", "Нажатие левого стика (L3)"),
        ("R3", "Нажатие правого стика (R3)"),
        ("STICK", "Левый аналоговый стик"),
        ("DPAD", "Крестовина (D-Pad)")
    ]

    public init() {}

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                // 1. Black Background with Long-Press gesture
                Color.black
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedId = nil
                    }
                    .onLongPressGesture(minimumDuration: 0.5, perform: {
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        showBgMenu = true
                    })

                // 2. Control Items (Buttons, Stick, D-Pad)
                ForEach(items) { item in
                    if !item.isHidden {
                        renderControlItem(item, in: geo)
                    }
                }

                // 3. Top Toolbar: appears when a button is selected or shows mode switch + actions
                VStack {
                    topToolbar
                        .padding(.top, 8)
                    Spacer()
                }

                // 4. Subtle Hint at bottom
                VStack {
                    Spacer()
                    Text("Тап — выбор • Зажмите кнопку — меню • Зажмите фон — главное меню")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.35))
                        .padding(.bottom, 6)
                }

                // 5. Toast Notification
                if let toast = showToast {
                    VStack {
                        Spacer()
                        Text(toast)
                            .font(.callout.weight(.medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(Color.black.opacity(0.85).clipShape(Capsule()))
                            .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                            .padding(.bottom, 36)
                            .transition(.opacity.combined(with: .scale))
                    }
                }
            }
            .onAppear {
                loadCurrentMode()
            }
            // Context Dialog for Background Long Press
            .confirmationDialog("Действия редактора (\(is3DMode ? "3D" : "2D"))", isPresented: $showBgMenu, titleVisibility: .visible) {
                Button("➕ Добавить кнопку") {
                    showAddPicker = true
                }
                Button("💾 Сохранить изменения") {
                    saveChanges()
                }
                Button("↺ Вернуть начальные для \(is3DMode ? "3D" : "2D")", role: .destructive) {
                    resetToDefault()
                }
                Button("🚪 Выйти из редактора", role: .cancel) {
                    requestExit()
                }
            }
            // Add Button Sheet / Dialog
            .confirmationDialog("Выберите кнопку для добавления", isPresented: $showAddPicker, titleVisibility: .visible) {
                ForEach(availableSwitchButtons, id: \.0) { btn in
                    Button(btn.1) {
                        addButton(id: btn.0, name: btn.0)
                    }
                }
                Button("Отмена", role: .cancel) {}
            }
            // Unsaved Changes Confirmation Alert
            .alert("Несохраненные изменения", isPresented: $showExitAlert) {
                Button("Сохранить (выйти)") {
                    saveChanges()
                    dismiss()
                }
                Button("Не сохранять (выйти)", role: .destructive) {
                    dismiss()
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Вы внесли изменения в раскладку управления (\(is3DMode ? "3D" : "2D")). Сохранить их перед выходом?")
            }
        }
    }

    // MARK: - Control Item Rendering (Matches in-game CAShapeLayer appearance 1:1)
    @ViewBuilder
    private func renderControlItem(_ item: ControlButtonConfig, in geo: GeometryProxy) -> some View {
        let isSelected = selectedId == item.id
        let currentWidth = item.baseWidth * item.scale
        let currentHeight = item.baseHeight * item.scale
        let posX = item.x * geo.size.width
        let posY = item.y * geo.size.height

        ZStack {
            if item.isStick {
                // In-game Left Stick: large outer ring + knob with inner concentric circle
                Circle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: currentWidth, height: currentHeight)
                    .overlay(Circle().stroke(Color.white.opacity(0.38), lineWidth: 1.5))
                Circle()
                    .fill(Color.white.opacity(0.14))
                    .frame(width: currentWidth * 0.39, height: currentHeight * 0.39)
                    .overlay(Circle().stroke(Color.white.opacity(0.38), lineWidth: 1.5))
                    .overlay(Circle().stroke(Color.white.opacity(0.38), lineWidth: 1.5).scaleEffect(0.62))
            } else if item.isDpad {
                // In-game D-Pad Cross
                ZStack {
                    RoundedRectangle(cornerRadius: 6 * item.scale)
                        .fill(Color.white.opacity(0.14))
                        .frame(width: currentWidth, height: currentHeight * 0.35)
                        .overlay(RoundedRectangle(cornerRadius: 6 * item.scale).stroke(Color.white.opacity(0.38), lineWidth: 1.5))
                    RoundedRectangle(cornerRadius: 6 * item.scale)
                        .fill(Color.white.opacity(0.14))
                        .frame(width: currentWidth * 0.35, height: currentHeight)
                        .overlay(RoundedRectangle(cornerRadius: 6 * item.scale).stroke(Color.white.opacity(0.38), lineWidth: 1.5))
                }
            } else {
                // In-game Button: Teardrop (ZL/L/ZR/R), Capsule (+/−), or Circle (ABXY/L3/R3)
                let isPill = item.id == "PLUS" || item.id == "MINUS"
                let isLeftDrop = item.id == "ZL" || item.id == "L"
                let isRightDrop = item.id == "ZR" || item.id == "R"

                if isPill {
                    Capsule()
                        .fill(Color.white.opacity(0.14))
                        .frame(width: currentWidth, height: currentHeight)
                        .overlay(Capsule().stroke(item.isToggle ? Color.cyan : Color.white.opacity(0.38), lineWidth: item.isToggle ? 1.8 : 1.5))
                } else if isLeftDrop {
                    // Teardrop pointing toward top-left corner
                    UnevenRoundedRectangle(topLeadingRadius: 4 * item.scale, bottomLeadingRadius: 26 * item.scale, bottomTrailingRadius: 26 * item.scale, topTrailingRadius: 26 * item.scale)
                        .fill(Color.white.opacity(0.14))
                        .frame(width: currentWidth, height: currentHeight)
                        .overlay(UnevenRoundedRectangle(topLeadingRadius: 4 * item.scale, bottomLeadingRadius: 26 * item.scale, bottomTrailingRadius: 26 * item.scale, topTrailingRadius: 26 * item.scale).stroke(item.isToggle ? Color.cyan : Color.white.opacity(0.38), lineWidth: item.isToggle ? 2.0 : 1.5))
                } else if isRightDrop {
                    // Teardrop pointing toward top-right corner
                    UnevenRoundedRectangle(topLeadingRadius: 26 * item.scale, bottomLeadingRadius: 26 * item.scale, bottomTrailingRadius: 26 * item.scale, topTrailingRadius: 4 * item.scale)
                        .fill(Color.white.opacity(0.14))
                        .frame(width: currentWidth, height: currentHeight)
                        .overlay(UnevenRoundedRectangle(topLeadingRadius: 26 * item.scale, bottomLeadingRadius: 26 * item.scale, bottomTrailingRadius: 26 * item.scale, topTrailingRadius: 4 * item.scale).stroke(item.isToggle ? Color.cyan : Color.white.opacity(0.38), lineWidth: item.isToggle ? 2.0 : 1.5))
                } else {
                    Circle()
                        .fill(Color.white.opacity(0.14))
                        .frame(width: currentWidth, height: currentHeight)
                        .overlay(Circle().stroke(item.isToggle ? Color.cyan : Color.white.opacity(0.38), lineWidth: item.isToggle ? 1.8 : 1.5))
                }

                VStack(spacing: 0) {
                    Text(item.name)
                        .font(.system(size: (item.baseHeight * 0.36) * item.scale, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.85))

                    if item.isToggle {
                        Text("[T]")
                            .font(.system(size: 8 * item.scale, weight: .black))
                            .foregroundColor(Color.cyan)
                    }
                }
            }

            // Hitbox outline when selected
            if isSelected {
                Rectangle()
                    .stroke(Color.cyan, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .frame(width: currentWidth + 12, height: currentHeight + 12)
            }
        }
        .opacity(Double(item.opacity))
        .position(x: posX, y: posY)
        // Gestures: Tap to select, Drag to move
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { val in
                    if selectedId != item.id {
                        selectedId = item.id
                    }
                    if let idx = items.firstIndex(where: { $0.id == item.id }) {
                        let newNormX = max(0.03, min(0.97, val.location.x / geo.size.width))
                        let newNormY = max(0.04, min(0.96, val.location.y / geo.size.height))
                        items[idx].x = newNormX
                        items[idx].y = newNormY
                        hasChanges = true
                    }
                }
        )
        // Context Menu on Long Press on Button
        .contextMenu {
            // 1. Remap Menu
            Menu {
                ForEach(availableSwitchButtons, id: \.0) { btn in
                    Button(btn.1) {
                        remapButton(item.id, to: btn.0, name: btn.0)
                    }
                }
            } label: {
                Label("Изменить кнопку (\(item.mapping))", systemImage: "arrow.triangle.2.circlepath")
            }

            // 2. Opacity Submenu
            Menu {
                Button("100% (Стандарт)") { setOpacity(item.id, 1.0) }
                Button("75%") { setOpacity(item.id, 0.75) }
                Button("50% (Полупрозрачная)") { setOpacity(item.id, 0.50) }
                Button("25% (Едва заметная)") { setOpacity(item.id, 0.25) }
            } label: {
                Label("Прозрачность (\(Int(item.opacity * 100))%)", systemImage: "eye")
            }

            // 3. Toggle Mode switch in menu
            Button {
                toggleMode(item.id)
            } label: {
                Label(item.isToggle ? "Режим: Переключение [T]" : "Режим: Зажатие (Hold)", systemImage: item.isToggle ? "checkmark.circle.fill" : "circle")
            }

            // 4. Delete Button
            Button(role: .destructive) {
                deleteButton(item.id)
            } label: {
                Label("Удалить кнопку", systemImage: "trash")
            }
        }
    }

    // MARK: - Top Toolbar
    @ViewBuilder
    private var topToolbar: some View {
        if let selId = selectedId, let idx = items.firstIndex(where: { $0.id == selId }) {
            let item = items[idx]
            HStack(spacing: 14) {
                // Button identifier badge
                Text(item.name.isEmpty ? item.id : item.name)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.cyan)
                    .frame(minWidth: 26)

                Divider()
                    .frame(height: 18)
                    .background(Color.white.opacity(0.3))

                // Size Adjustment: [-] Size: 100% [+]
                HStack(spacing: 8) {
                    Button(action: {
                        let newScale = max(0.5, round((item.scale - 0.05) * 100) / 100)
                        items[idx].scale = newScale
                        hasChanges = true
                    }) {
                        Image(systemName: "minus.circle.fill")
                            .font(.title3)
                            .foregroundColor(.white)
                    }

                    Text("Размер: \(Int(round(item.scale * 100)))%")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundColor(.white)
                        .frame(minWidth: 92, alignment: .center)

                    Button(action: {
                        let newScale = min(2.0, round((item.scale + 0.05) * 100) / 100)
                        items[idx].scale = newScale
                        hasChanges = true
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(.white)
                    }
                }

                Divider()
                    .frame(height: 18)
                    .background(Color.white.opacity(0.3))

                // Toggle vs Hold Checkbox
                Button(action: {
                    items[idx].isToggle.toggle()
                    hasChanges = true
                    let gen = UIImpactFeedbackGenerator(style: .light)
                    gen.impactOccurred()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: item.isToggle ? "checkmark.square.fill" : "square")
                            .foregroundColor(item.isToggle ? .cyan : .gray)
                        Text(item.isToggle ? "Переключение (Toggle)" : "Зажатие (Hold)")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(item.isToggle ? .cyan : .white.opacity(0.85))
                    }
                }

                Divider()
                    .frame(height: 18)
                    .background(Color.white.opacity(0.3))

                // Deselect
                Button(action: { selectedId = nil }) {
                    Image(systemName: "xmark.circle")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color(white: 0.12).opacity(0.92).clipShape(Capsule()))
            .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
        } else {
            // Main menu toolbar: 2D/3D Mode Switcher + Actions
            HStack(spacing: 12) {
                // 2D vs 3D Layout Switcher
                HStack(spacing: 0) {
                    Button(action: { switchMode(is3D: false) }) {
                        Text("2D Режим")
                            .font(.subheadline.weight(!is3DMode ? .bold : .regular))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(!is3DMode ? Color.blue : Color.clear)
                            .foregroundColor(!is3DMode ? .white : .white.opacity(0.6))
                            .clipShape(Capsule())
                    }
                    Button(action: { switchMode(is3D: true) }) {
                        Text("3D Режим")
                            .font(.subheadline.weight(is3DMode ? .bold : .regular))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(is3DMode ? Color.blue : Color.clear)
                            .foregroundColor(is3DMode ? .white : .white.opacity(0.6))
                            .clipShape(Capsule())
                    }
                }
                .padding(3)
                .background(Color.white.opacity(0.12).clipShape(Capsule()))

                Divider()
                    .frame(height: 20)
                    .background(Color.white.opacity(0.25))

                Button(action: { showBgMenu = true }) {
                    Label("Меню", systemImage: "ellipsis.circle")
                        .font(.callout.weight(.medium))
                }
                .buttonStyle(.bordered)
                .tint(.white)

                Button(action: { saveChanges() }) {
                    Label("Сохранить", systemImage: "checkmark.circle.fill")
                        .font(.callout.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)

                Button(action: { requestExit() }) {
                    Label("Выйти", systemImage: "xmark")
                        .font(.callout.weight(.medium))
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.70).clipShape(Capsule()))
            .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.8))
        }
    }

    // MARK: - Actions
    private func loadCurrentMode() {
        let loaded = ControlsLayoutStore.loadLayout(is3D: is3DMode)
        items = loaded
        originalItems = loaded
        selectedId = nil
        hasChanges = false
    }

    private func switchMode(is3D: Bool) {
        if is3D == is3DMode { return }
        if hasChanges {
            ControlsLayoutStore.saveLayout(items, is3D: is3DMode)
        }
        is3DMode = is3D
        loadCurrentMode()
        showToastMessage("Редактирование: \(is3D ? "3D" : "2D") раскладка")
    }

    private func remapButton(_ id: String, to newMapping: String, name: String) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].mapping = newMapping
            items[idx].name = name
            hasChanges = true
            showToastMessage("Кнопка переназначена на: \(newMapping)")
        }
    }

    private func setOpacity(_ id: String, _ val: CGFloat) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].opacity = val
            hasChanges = true
            showToastMessage("Прозрачность: \(Int(val * 100))%")
        }
    }

    private func toggleMode(_ id: String) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].isToggle.toggle()
            hasChanges = true
            showToastMessage(items[idx].isToggle ? "Включен режим Toggle [T]" : "Включен обычный Hold")
        }
    }

    private func deleteButton(_ id: String) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].isHidden = true
            if selectedId == id { selectedId = nil }
            hasChanges = true
            showToastMessage("Кнопка удалена (можно вернуть через меню)")
        }
    }

    private func addButton(id: String, name: String) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].isHidden = false
            items[idx].x = 0.5
            items[idx].y = 0.5
            selectedId = id
            hasChanges = true
            showToastMessage("Кнопка \(name) добавлена в центр экрана")
        } else {
            let newItem = ControlButtonConfig(id: id, name: name, x: 0.5, y: 0.5)
            items.append(newItem)
            selectedId = id
            hasChanges = true
            showToastMessage("Кнопка \(name) добавлена")
        }
    }

    private func saveChanges() {
        ControlsLayoutStore.saveLayout(items, is3D: is3DMode)
        originalItems = items
        hasChanges = false
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.success)
        showToastMessage("Раскладка (\(is3DMode ? "3D" : "2D")) сохранена!")
    }

    private func resetToDefault() {
        items = ControlsLayoutStore.defaultLayout(is3D: is3DMode)
        ControlsLayoutStore.resetLayout(is3D: is3DMode)
        originalItems = items
        hasChanges = false
        selectedId = nil
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.warning)
        showToastMessage("Сброшено к начальным для \(is3DMode ? "3D" : "2D")")
    }

    private func requestExit() {
        if hasChanges {
            showExitAlert = true
        } else {
            dismiss()
        }
    }

    private func showToastMessage(_ msg: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            showToast = msg
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeInOut(duration: 0.3)) {
                if showToast == msg { showToast = nil }
            }
        }
    }
}

@_cdecl("dm_show_controls_editor")
public func dmShowControlsEditor(_ viewController: UnsafeMutableRawPointer) {
    let parent = Unmanaged<UIViewController>.fromOpaque(viewController).takeUnretainedValue()
    let editor = ControlsEditorView()
    let host = UIHostingController(rootView: editor)
    host.modalPresentationStyle = .fullScreen
    parent.present(host, animated: true)
}
