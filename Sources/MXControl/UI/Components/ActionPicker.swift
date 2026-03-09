import SwiftUI

/// Predefined actions for button remapping.
///
/// These map to HID++ CIDs or virtual actions that the MX Master 3S supports.
/// For CID-based remaps, the device maps the button to behave like another button.
/// For "Default", the remap is cleared (CID 0).
enum ButtonAction: Hashable, CaseIterable, CustomStringConvertible {
    case defaultAction
    case middleClick
    case back
    case forward
    case gestureButton
    case smartShiftToggle
    case doNothing

    /// The CID to send as remap target (0 = restore default).
    var remapCID: UInt16 {
        switch self {
        case .defaultAction: return 0
        case .middleClick: return 82
        case .back: return 83
        case .forward: return 86
        case .gestureButton: return 195
        case .smartShiftToggle: return 196
        case .doNothing: return 0   // Divert + no handler = do nothing
        }
    }

    /// Whether this action requires diverting the button to software.
    var requiresDivert: Bool {
        self == .doNothing
    }

    var description: String {
        displayName
    }

    /// Human-readable action name.
    var displayName: String {
        switch self {
        case .defaultAction: return "Default"
        case .middleClick: return "Middle Click"
        case .back: return "Back"
        case .forward: return "Forward"
        case .gestureButton: return "Gesture"
        case .smartShiftToggle: return "SmartShift"
        case .doNothing: return "Do Nothing"
        }
    }

    /// SF Symbol name for this action.
    var systemImage: String {
        switch self {
        case .defaultAction: return "arrow.uturn.backward"
        case .middleClick: return "computermouse"
        case .back: return "chevron.left"
        case .forward: return "chevron.right"
        case .gestureButton: return "hand.draw"
        case .smartShiftToggle: return "arrow.up.arrow.down.circle"
        case .doNothing: return "nosign"
        }
    }

    /// Create from a remap target CID.
    static func from(cid: UInt16) -> ButtonAction {
        switch cid {
        case 0: return .defaultAction
        case 82: return .middleClick
        case 83: return .back
        case 86: return .forward
        case 195: return .gestureButton
        case 196: return .smartShiftToggle
        default: return .defaultAction
        }
    }
}

/// A compact picker dropdown for remapping a mouse button to a predefined action.
struct ActionPicker: View {
    let buttonName: String
    let controlId: UInt16
    @Binding var currentAction: ButtonAction
    var onChanged: ((ButtonAction) -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Text(buttonName)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)

            Spacer()

            Picker("", selection: $currentAction) {
                ForEach(ButtonAction.allCases, id: \.self) { action in
                    Label(action.displayName, systemImage: action.systemImage)
                        .tag(action)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 160)
            .onChange(of: currentAction) { _, newAction in
                onChanged?(newAction)
            }
        }
    }
}
