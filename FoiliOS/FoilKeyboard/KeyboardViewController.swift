import UIKit

final class KeyboardViewController: UIInputViewController {
    private let stack = UIStackView()
    private let statusLabel = UILabel()
    private let startButton = UIButton(type: .system)
    private let insertButton = UIButton(type: .system)
    private let nextKeyboardButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        configureActions()
    }

    private func configureView() {
        view.backgroundColor = .systemBackground

        statusLabel.text = "Foil keyboard"
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.textAlignment = .center

        startButton.setTitle("Start", for: .normal)
        startButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)

        insertButton.setTitle("Insert shell text", for: .normal)
        insertButton.titleLabel?.font = .preferredFont(forTextStyle: .body)

        nextKeyboardButton.setTitle("Next Keyboard", for: .normal)
        nextKeyboardButton.titleLabel?.font = .preferredFont(forTextStyle: .caption1)

        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(statusLabel)
        stack.addArrangedSubview(startButton)
        stack.addArrangedSubview(insertButton)
        stack.addArrangedSubview(nextKeyboardButton)

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.layoutMarginsGuide.bottomAnchor, constant: -8),
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 180)
        ])
    }

    private func configureActions() {
        startButton.addTarget(self, action: #selector(startTapped), for: .touchUpInside)
        insertButton.addTarget(self, action: #selector(insertTapped), for: .touchUpInside)
        nextKeyboardButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
    }

    @objc private func startTapped() {
        statusLabel.text = "Start shell tapped"
    }

    @objc private func insertTapped() {
        textDocumentProxy.insertText(FoilIOSConstants.fakeTranscript)
    }
}
