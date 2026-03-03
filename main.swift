import AppKit
import SwiftUI
import CoreGraphics


// MARK: - Event Tap (Cmd+V → digit)

var tapMachPort: CFMachPort?

func digitFromKeyCode(_ kc: Int64) -> Int? {
	switch kc {
	case 18: return 1; case 19: return 2; case 20: return 3
	case 21: return 4; case 23: return 5; case 22: return 6
	case 26: return 7; case 28: return 8; case 25: return 9
	case 29: return 0; default: return nil
	}
}

func eventTapCallback(
	proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
	if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
		if let port = tapMachPort { CGEvent.tapEnable(tap: port, enable: true) }
		return Unmanaged.passUnretained(event)
	}
	guard type == .keyDown else { return Unmanaged.passUnretained(event) }

	let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
	let flags = event.flags

	// Ctrl + digit (no other modifiers)
	let hasCtrl = flags.contains(.maskControl)
	let hasCmd = flags.contains(.maskCommand)
	let hasShift = flags.contains(.maskShift)
	let hasOpt = flags.contains(.maskAlternate)

	if hasCtrl && !hasCmd && !hasShift && !hasOpt, let digit = digitFromKeyCode(keyCode) {
		let slot = digit == 0 ? 10 : digit
		DispatchQueue.main.async { (NSApp.delegate as? Stash)?.pasteSlot(slot) }
		return nil // suppress the key
	}

	return Unmanaged.passUnretained(event)
}

// MARK: - App

class Stash: NSObject, NSApplicationDelegate {
	var statusItem: NSStatusItem!
	var store = ClipStore()
	var manageWindow: NSWindow?
	var toast: ToastWindow?

	func applicationDidFinishLaunching(_ n: Notification) {

		statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
		if let btn = statusItem.button {
			btn.image = NSImage(systemSymbolName: "tray.2.fill", accessibilityDescription: "Stash")
		}

		let menu = NSMenu()
		let header = NSMenuItem(title: "Stash — Ctrl+1 to 0", action: nil, keyEquivalent: "")
		header.isEnabled = false
		menu.addItem(header)
		menu.addItem(.separator())
		menu.addItem(NSMenuItem(title: "Manage Clips…", action: #selector(openManager), keyEquivalent: ","))
		menu.addItem(.separator())
		menu.addItem(NSMenuItem(title: "Quit Stash", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
		statusItem.menu = menu

		let trusted = AXIsProcessTrusted()

		if !trusted {
			let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
			AXIsProcessTrustedWithOptions(opts)
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
				let alert = NSAlert()
				alert.messageText = "Stash needs Accessibility"
				alert.informativeText = "Stash needs Accessibility permission for Ctrl+1-0 paste shortcuts.\n\nSystem Settings → Privacy & Security → Accessibility → Enable Stash"
				alert.alertStyle = .informational
				alert.addButton(withTitle: "Open Settings")
				alert.addButton(withTitle: "Later")
				NSApp.activate(ignoringOtherApps: true)
				if alert.runModal() == .alertFirstButtonReturn {
					NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
				}
			}
		}

		let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
		if let tap = CGEvent.tapCreate(
			tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
			eventsOfInterest: eventMask, callback: eventTapCallback, userInfo: nil
		) {
			tapMachPort = tap
			let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
			CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
			CGEvent.tapEnable(tap: tap, enable: true)
		}
	}

	func pasteSlot(_ slot: Int) {
		guard let clip = store.clip(forSlot: slot) else {
			return
		}

		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(clip.content, forType: .string)

		DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
			Self.simulatePaste()
			self?.showToast(clip.preview, slot: slot)
		}
	}

	func showToast(_ label: String, slot: Int) {
		toast?.orderOut(nil)
		let w = ToastWindow(label: label, slot: slot)
		toast = w
		DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
			NSAnimationContext.runAnimationGroup({ ctx in
				ctx.duration = 0.3
				self?.toast?.animator().alphaValue = 0
			}, completionHandler: {
				self?.toast?.orderOut(nil)
				self?.toast = nil
			})
		}
	}

	@objc func openManager() {
		if let w = manageWindow {
			NSApp.activate(ignoringOtherApps: true)
			w.makeKeyAndOrderFront(nil)
			return
		}
		let w = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 520, height: 500),
			styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
			backing: .buffered, defer: false
		)
		w.title = "Stash"
		w.titlebarAppearsTransparent = true
		w.isMovableByWindowBackground = true
		w.backgroundColor = .clear

		let visual = NSVisualEffectView(frame: w.contentView!.bounds)
		visual.autoresizingMask = [.width, .height]
		visual.material = .hudWindow
		visual.blendingMode = .behindWindow
		visual.state = .active
		w.contentView?.addSubview(visual)

		let host = NSHostingView(rootView: ManagerView(store: store))
		host.frame = w.contentView!.bounds
		host.autoresizingMask = [.width, .height]
		w.contentView?.addSubview(host)

		w.center()
		w.isReleasedWhenClosed = false
		manageWindow = w
		NSApp.activate(ignoringOtherApps: true)
		w.makeKeyAndOrderFront(nil)
	}

	static func simulatePaste() {
		let src = CGEventSource(stateID: .hidSystemState)
		let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true)
		let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
		keyDown?.flags = .maskCommand
		keyUp?.flags = .maskCommand
		keyDown?.post(tap: .cghidEventTap)
		keyUp?.post(tap: .cghidEventTap)
	}
}

// MARK: - Toast

class ToastWindow: NSPanel {
	init(label: String, slot: Int) {
		let w: CGFloat = 240, h: CGFloat = 44
		var origin = NSPoint(x: 0, y: 0)
		if let screen = NSScreen.main {
			let f = screen.visibleFrame
			origin = NSPoint(x: f.midX - w / 2, y: f.maxY - h - 80)
		}
		super.init(
			contentRect: NSRect(origin: origin, size: NSSize(width: w, height: h)),
			styleMask: [.nonactivatingPanel, .fullSizeContentView],
			backing: .buffered, defer: false
		)
		titleVisibility = .hidden
		titlebarAppearsTransparent = true
		level = .floating
		backgroundColor = .clear
		isOpaque = false
		hasShadow = true
		isReleasedWhenClosed = false

		let view = ToastView(label: label, slot: slot)
		contentView = NSHostingView(rootView: view)
		makeKeyAndOrderFront(nil)
	}
}

struct ToastView: View {
	let label: String
	let slot: Int

	var body: some View {
		HStack(spacing: 10) {
			Image(systemName: "checkmark.circle.fill")
				.foregroundStyle(.green)
				.font(.system(size: 16, weight: .medium))
			Text("Pasted")
				.font(.system(size: 12, weight: .medium))
				.foregroundStyle(.secondary)
			Text(label)
				.font(.system(size: 12, weight: .semibold))
				.lineLimit(1)
		}
		.padding(.horizontal, 16)
		.padding(.vertical, 10)
		.frame(maxWidth: .infinity)
		.background(.ultraThinMaterial)
		.clipShape(Capsule())
	}
}

// MARK: - Data

struct Clip: Identifiable, Codable, Hashable {
	let id: UUID
	var content: String
	var slot: Int
	init(id: UUID = UUID(), content: String, slot: Int) {
		self.id = id; self.content = content; self.slot = slot
	}
	var displayKey: String { slot == 10 ? "0" : "\(slot)" }
	var preview: String {
		let first = content.prefix(60).replacingOccurrences(of: "\n", with: " ")
		return content.count > 60 ? first + "…" : String(first)
	}
}

class ClipStore: ObservableObject {
	@Published var clips: [Clip] = []
	private let key = "stash.clips"

	init() {
		if let d = UserDefaults.standard.data(forKey: key),
		   let c = try? JSONDecoder().decode([Clip].self, from: d) {
			clips = c
		} else if let oldDefaults = UserDefaults(suiteName: "com.clippy1000.app"),
				  let d = oldDefaults.data(forKey: "clippy1000.prompts"),
				  let old = try? JSONDecoder().decode([Clip].self, from: d) {
			clips = old; save()
		}
	}
	func save() {
		if let d = try? JSONEncoder().encode(clips) { UserDefaults.standard.set(d, forKey: key) }
	}
	func add(content: String) {
		guard clips.count < 10 else { return }
		clips.append(Clip(content: content, slot: clips.count + 1))
		save()
	}
	func delete(_ c: Clip) { clips.removeAll { $0.id == c.id }; reindex(); save() }
	func update(_ c: Clip) {
		if let i = clips.firstIndex(where: { $0.id == c.id }) { clips[i] = c; save() }
	}
	func move(from s: IndexSet, to d: Int) { clips.move(fromOffsets: s, toOffset: d); reindex(); save() }
	func clip(forSlot s: Int) -> Clip? { clips.first { $0.slot == s } }
	private func reindex() { for i in clips.indices { clips[i].slot = i + 1 } }
}

// MARK: - Manager View

struct ManagerView: View {
	@ObservedObject var store: ClipStore
	@State private var showAdd = false
	@State private var editing: Clip?
	@State private var hovered: UUID?

	var body: some View {
		VStack(spacing: 0) {
			// Header
			HStack(alignment: .center) {
				VStack(alignment: .leading, spacing: 2) {
					Text("Stash").font(.system(size: 20, weight: .bold, design: .rounded))
					Text("Ctrl+1 through Ctrl+0 to paste")
						.font(.system(size: 11))
						.foregroundStyle(.secondary)
				}
				Spacer()
				Text("\(store.clips.count)/10")
					.font(.system(size: 11, weight: .medium, design: .monospaced))
					.foregroundStyle(.tertiary)
					.padding(.horizontal, 8)
					.padding(.vertical, 4)
					.background(.quaternary.opacity(0.5))
					.clipShape(Capsule())
				Button(action: { showAdd = true }) {
					Image(systemName: "plus")
						.font(.system(size: 12, weight: .semibold))
						.frame(width: 28, height: 28)
						.background(.quaternary.opacity(0.5))
						.clipShape(Circle())
				}
				.buttonStyle(.plain)
				.disabled(store.clips.count >= 10)
			}
			.padding(.horizontal, 20)
			.padding(.top, 16)
			.padding(.bottom, 12)

			Divider().padding(.horizontal, 16)

			if store.clips.isEmpty {
				Spacer()
				VStack(spacing: 12) {
					Image(systemName: "tray.2.fill")
						.font(.system(size: 36))
						.foregroundStyle(.quaternary)
					Text("Nothing stashed yet")
						.font(.system(size: 15, weight: .medium))
						.foregroundStyle(.secondary)
					Button(action: { showAdd = true }) {
						Text("Stash Something")
							.font(.system(size: 12, weight: .medium))
							.padding(.horizontal, 16)
							.padding(.vertical, 6)
							.background(Color.accentColor)
							.foregroundStyle(.white)
							.clipShape(Capsule())
					}
					.buttonStyle(.plain)
				}
				Spacer()
			} else {
				ScrollView {
					LazyVStack(spacing: 2) {
						ForEach(store.clips) { clip in
							ClipRow(clip: clip, isHovered: hovered == clip.id)
								.onHover { h in hovered = h ? clip.id : nil }
								.onTapGesture(count: 2) { editing = clip }
								.contextMenu {
									Button("Edit…") { editing = clip }
									Divider()
									Button("Delete", role: .destructive) { store.delete(clip) }
								}
						}
						.onMove { store.move(from: $0, to: $1) }
					}
					.padding(.horizontal, 12)
					.padding(.vertical, 8)
				}
			}
		}
		.frame(minWidth: 440, minHeight: 380)
		.sheet(isPresented: $showAdd) {
			EditSheet(mode: .add) { c in store.add(content: c) }
		}
		.sheet(item: $editing) { clip in
			EditSheet(mode: .edit(clip)) { c in
				var u = clip; u.content = c; store.update(u)
			}
		}
	}
}

struct ClipRow: View {
	let clip: Clip
	let isHovered: Bool

	var body: some View {
		HStack(spacing: 12) {
			Text(clip.displayKey)
				.font(.system(size: 13, weight: .bold, design: .monospaced))
				.foregroundStyle(.white)
				.frame(width: 28, height: 28)
				.background(Color.accentColor)
				.clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

			Text(clip.content)
				.font(.system(size: 12))
				.foregroundStyle(.primary)
				.lineLimit(2)

			Spacer()

			HStack(spacing: 2) {
				Text("⌃")
					.font(.system(size: 10, weight: .medium, design: .monospaced))
				Text(clip.displayKey)
					.font(.system(size: 10, weight: .bold, design: .monospaced))
			}
			.foregroundStyle(.tertiary)
			.padding(.horizontal, 8)
			.padding(.vertical, 4)
			.background(.quaternary.opacity(0.3))
			.clipShape(Capsule())
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 10)
		.background(
			RoundedRectangle(cornerRadius: 8, style: .continuous)
				.fill(isHovered ? Color.primary.opacity(0.06) : .clear)
		)
		.contentShape(Rectangle())
	}
}

// MARK: - Edit Sheet

enum EditMode: Identifiable {
	case add, edit(Clip)
	var id: String {
		switch self { case .add: "add"; case .edit(let c): c.id.uuidString }
	}
}

struct EditSheet: View {
	let mode: EditMode
	let onSave: (String) -> Void
	@Environment(\.dismiss) var dismiss
	@State var content: String

	init(mode: EditMode, onSave: @escaping (String) -> Void) {
		self.mode = mode; self.onSave = onSave
		switch mode {
		case .add: _content = State(initialValue: "")
		case .edit(let c): _content = State(initialValue: c.content)
		}
	}

	var isValid: Bool { !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

	var body: some View {
		VStack(spacing: 16) {
			HStack {
				Text({ switch mode { case .add: return "Stash"; case .edit: return "Edit" } }())
					.font(.system(size: 15, weight: .semibold))
				Spacer()
			}

			TextEditor(text: $content)
				.font(.system(size: 12, design: .monospaced))
				.frame(minHeight: 160)
				.scrollContentBackground(.hidden)
				.padding(8)
				.background(
					RoundedRectangle(cornerRadius: 8, style: .continuous)
						.fill(.quaternary.opacity(0.3))
				)
				.overlay(
					RoundedRectangle(cornerRadius: 8, style: .continuous)
						.stroke(.quaternary, lineWidth: 1)
				)

			HStack {
				Button("Cancel") { dismiss() }
					.keyboardShortcut(.cancelAction)
				Spacer()
				Button(action: {
					onSave(content.trimmingCharacters(in: .whitespacesAndNewlines))
					dismiss()
				}) {
					Text("Save")
						.font(.system(size: 12, weight: .medium))
						.padding(.horizontal, 20)
						.padding(.vertical, 6)
						.background(isValid ? Color.accentColor : Color.gray.opacity(0.3))
						.foregroundStyle(.white)
						.clipShape(Capsule())
				}
				.buttonStyle(.plain)
				.disabled(!isValid)
				.keyboardShortcut(.defaultAction)
			}
		}
		.padding(24)
		.frame(width: 400)
	}
}

// MARK: - Launch

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let stash = Stash()
app.delegate = stash
app.run()
