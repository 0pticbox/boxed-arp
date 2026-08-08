import AppKit
import AudioToolbox
import CoreAudioKit
import SwiftUI

public final class AudioUnitViewController: AUViewController, AUAudioUnitFactory {
    private var boxedAudioUnit: BoxedArpAudioUnit?
    private var hostingController: NSHostingController<PicoArpView>?

    public override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 340))
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = NSSize(width: 720, height: 340)
        installInterfaceIfReady()
    }

    public func createAudioUnit(with componentDescription: AudioComponentDescription) throws -> AUAudioUnit {
        let unit = try BoxedArpAudioUnit(componentDescription: componentDescription, options: [])
        boxedAudioUnit = unit
        DispatchQueue.main.async { [weak self] in
            self?.installInterfaceIfReady()
        }
        return unit
    }

    private func installInterfaceIfReady() {
        guard isViewLoaded, hostingController == nil, let boxedAudioUnit else { return }

        let model = ArpViewModel(audioUnit: boxedAudioUnit)
        let host = NSHostingController(rootView: PicoArpView(model: model))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)

        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.widthAnchor.constraint(greaterThanOrEqualToConstant: 560),
            host.view.heightAnchor.constraint(greaterThanOrEqualToConstant: 300)
        ])

        hostingController = host
    }
}
