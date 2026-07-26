import SwiftUI

/// 画像メモの切り替え時に適用するアニメーションの種類。
/// 設定パネルのセレクトボックスから選択され、UserDefaults に rawValue で永続化される。
enum ImageTransitionStyle: String, CaseIterable, Identifiable {
    case none
    case fade
    case slideHorizontal
    case slideVertical
    case zoom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "なし（即時切り替え）"
        case .fade: return "フェード"
        case .slideHorizontal: return "スライド（横）"
        case .slideVertical: return "スライド（縦）"
        case .zoom: return "ズーム"
        }
    }

    var transition: AnyTransition {
        switch self {
        case .none:
            return .identity
        case .fade:
            return .opacity
        case .slideHorizontal:
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        case .slideVertical:
            return .asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .move(edge: .top).combined(with: .opacity)
            )
        case .zoom:
            return .scale(scale: 0.85).combined(with: .opacity)
        }
    }

    /// `withAnimation` に渡すアニメーション。`nil` なら即時切り替え。
    var animation: Animation? {
        switch self {
        case .none: return nil
        case .fade: return .easeInOut(duration: 0.5)
        case .slideHorizontal, .slideVertical: return .easeInOut(duration: 0.4)
        case .zoom: return .spring(response: 0.45, dampingFraction: 0.85)
        }
    }
}
