import SwiftUI
import UIKit

/// 点屏幕任何空白处都收起键盘。
/// SwiftUI 自己没有这个能力，所以直接给整个窗口挂一个手势。
/// cancelsTouchesInView = false 是关键：手势只"顺便听一下"，
/// 不会把点击吞掉，按钮、列表该响应还是照常响应。
final class KeyboardDismisser: NSObject, UIGestureRecognizerDelegate {

    static let shared = KeyboardDismisser()
    private var installed = false

    func install() {
        guard !installed else { return }
        // 窗口可能还没建好，晚一点再挂
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow }) ?? UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first
            else { return }

            let tap = UITapGestureRecognizer(target: self, action: #selector(self.handleTap))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            window.addGestureRecognizer(tap)
            self.installed = true
        }
    }

    @objc private func handleTap() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }

    /// 允许跟其他手势一起工作，不然会跟滚动、点按打架
    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    /// 点在输入框自己身上时不收起，不然刚点进去就被关掉了
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view: UIView? = touch.view
        while let v = view {
            if v is UITextField || v is UITextView { return false }
            view = v.superview
        }
        return true
    }
}

/// 键盘现在是不是支起来的。
///
/// 输入框上下那点留白，键盘收着的时候要给导航条让位，
/// 键盘支起来的时候就该贴着键盘——不然中间空一大条，
/// 看着像输入框浮在半空。
@MainActor
final class KeyboardWatcher: ObservableObject {

    static let shared = KeyboardWatcher()

    @Published private(set) var up = false

    private init() {
        let center = NotificationCenter.default
        center.addObserver(forName: UIResponder.keyboardWillShowNotification,
                           object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.up = true }
        }
        center.addObserver(forName: UIResponder.keyboardWillHideNotification,
                           object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.up = false }
        }
    }
}

extension View {
    /// 手动收起键盘
    func hideKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }
}
