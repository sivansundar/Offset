//
//  OffsetApp.swift
//  Offset
//
//  Created by Sivan on 13/04/26.
//

import SwiftUI
import AppKit

@main
struct OffsetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let serviceHandler = ServiceHandler()
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = serviceHandler
        NSRegisterServicesProvider(serviceHandler, "Offset")
        NSUpdateDynamicServices()
        menuBarController = MenuBarController()
    }
}
