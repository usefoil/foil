import UIKit

final class KeyboardViewController: UIInputViewController {
    private let bridge = FoilKeyboardBridge()
    private let stack = UIStackView()
    private let statusLabel = UILabel()
    private let messageLabel = UILabel()
    private let startButton = UIButton(type: .system)
    private let insertButton = UIButton(type: .system)
    private let nextKeyboardButton = UIButton(type: .system)
    private var refreshTimer: Timer?
    private var latestSnapshot = FoilKeyboardSnapshot.initial

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        configureActions()
        refreshState()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            self?.refreshState()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func configureView() {
        view.backgroundColor = .systemBackground

        statusLabel.text = "Foil keyboard"
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.textAlignment = .center

        messageLabel.text = "Ready"
        messageLabel.font = .preferredFont(forTextStyle: .caption1)
        messageLabel.textAlignment = .center
        messageLabel.textColor = .secondaryLabel
        messageLabel.numberOfLines = 2

        startButton.setTitle("Start", for: .normal)
        startButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)

        insertButton.setTitle("Insert latest", for: .normal)
        insertButton.titleLabel?.font = .preferredFont(forTextStyle: .body)

        nextKeyboardButton.setTitle("Next Keyboard", for: .normal)
        nextKeyboardButton.titleLabel?.font = .preferredFont(forTextStyle: .caption1)

        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(statusLabel)
        stack.addArrangedSubview(messageLabel)
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
        bridge.requestHandoff()
        refreshState()
        openContainingApp()
    }

    @objc private func insertTapped() {
        guard let transcript = latestSnapshot.transcript, !transcript.isEmpty else { return }
        textDocumentProxy.insertText(transcript)
        bridge.reset()
        refreshState()
    }

    private func refreshState() {
        let snapshot = bridge.load()
        latestSnapshot = snapshot
        statusLabel.text = snapshot.phase.displayName
        messageLabel.text = snapshot.message
        insertButton.isEnabled = snapshot.transcript?.isEmpty == false
    }

    private func openContainingApp() {
        guard let url = URL(string: "\(FoilIOSConstants.appURLScheme)://start") else { return }
        extensionContext?.open(url)
    }
}
