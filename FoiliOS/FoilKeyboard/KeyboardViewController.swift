import UIKit

final class KeyboardViewController: UIInputViewController {
    private let bridge = FoilKeyboardBridge()
    private let stack = UIStackView()
    private let statusLabel = UILabel()
    private let messageLabel = UILabel()
    private let startButton = UIButton(type: .system)
    private let insertButton = UIButton(type: .system)
    private let nextKeyboardButton = UIButton(type: .system)
    private var heightConstraint: NSLayoutConstraint?
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
        view.accessibilityIdentifier = "foil-keyboard-root"

        statusLabel.text = "Foil keyboard"
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.textAlignment = .center
        statusLabel.accessibilityIdentifier = "foil-keyboard-status"

        messageLabel.text = "Ready"
        messageLabel.font = .preferredFont(forTextStyle: .caption1)
        messageLabel.textAlignment = .center
        messageLabel.textColor = .secondaryLabel
        messageLabel.numberOfLines = 3
        messageLabel.accessibilityIdentifier = "foil-keyboard-message"

        startButton.setTitle("Start", for: .normal)
        startButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        startButton.accessibilityIdentifier = "foil-keyboard-start"

        var insertConfiguration = UIButton.Configuration.filled()
        insertConfiguration.title = "Insert latest"
        insertConfiguration.cornerStyle = .medium
        insertConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 12, bottom: 14, trailing: 12)
        insertButton.configuration = insertConfiguration
        insertButton.accessibilityIdentifier = "foil-keyboard-insert-latest"

        nextKeyboardButton.setTitle("Next Keyboard", for: .normal)
        nextKeyboardButton.titleLabel?.font = .preferredFont(forTextStyle: .caption1)
        nextKeyboardButton.accessibilityIdentifier = "foil-keyboard-next"

        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(statusLabel)
        stack.addArrangedSubview(messageLabel)
        stack.addArrangedSubview(insertButton)
        stack.addArrangedSubview(startButton)
        stack.addArrangedSubview(nextKeyboardButton)

        view.addSubview(stack)
        let heightConstraint = view.heightAnchor.constraint(equalToConstant: 300)
        heightConstraint.priority = .defaultHigh
        self.heightConstraint = heightConstraint

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.layoutMarginsGuide.bottomAnchor, constant: -8),
            heightConstraint
        ])
    }

    private func configureActions() {
        startButton.addTarget(self, action: #selector(startTapped), for: .touchUpInside)
        insertButton.addTarget(self, action: #selector(insertTapped), for: .touchUpInside)
        nextKeyboardButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
    }

    @objc private func startTapped() {
        if !hasFullAccess {
            bridge.recordKeyboardHealth(fullAccessEnabled: false, snapshot: latestSnapshot)
            refreshState()
            openContainingApp(host: "keyboard-health", queryItems: [URLQueryItem(name: "fullAccess", value: "off")])
            return
        }
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
        let fullAccessEnabled = hasFullAccess
        bridge.recordKeyboardHealth(fullAccessEnabled: fullAccessEnabled, snapshot: snapshot)
        statusLabel.text = snapshot.phase.displayName
        messageLabel.text = fullAccessEnabled ? snapshot.message : "Allow Full Access required. Open Foil app to recover."
        let hasTranscript = snapshot.transcript?.isEmpty == false
        insertButton.isEnabled = hasTranscript && fullAccessEnabled
        startButton.setTitle(fullAccessEnabled ? "Start" : "Open Foil", for: .normal)
        var insertConfiguration = insertButton.configuration ?? .filled()
        insertConfiguration.title = insertTitle(hasTranscript: hasTranscript, fullAccessEnabled: fullAccessEnabled)
        insertConfiguration.baseBackgroundColor = hasTranscript && fullAccessEnabled ? .systemBlue : .systemGray4
        insertConfiguration.baseForegroundColor = hasTranscript && fullAccessEnabled ? .white : .secondaryLabel
        insertButton.configuration = insertConfiguration
    }

    private func insertTitle(hasTranscript: Bool, fullAccessEnabled: Bool) -> String {
        if !fullAccessEnabled {
            return "Insert latest (full access off)"
        }
        return hasTranscript ? "Insert latest" : "Insert latest (no transcript)"
    }

    private func openContainingApp() {
        openContainingApp(host: "start")
    }

    private func openContainingApp(host: String, queryItems: [URLQueryItem] = []) {
        var components = URLComponents()
        components.scheme = FoilIOSConstants.appURLScheme
        components.host = host
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else { return }
        extensionContext?.open(url) { [weak self] success in
            guard !success else { return }
            DispatchQueue.main.async {
                self?.messageLabel.text = "Open Foil app from Home to recover."
            }
        }
    }
}
