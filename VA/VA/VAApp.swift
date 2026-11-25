//
//  VAApp.swift
//  VA
//
//  Created by Visakha on 10/29/26.
//

import SwiftUI
import VACore

@main
struct VAApp: App {
  init() {
    VALogger.log.info("Version \(marketingVersion) build \(buildVersion)")
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
    }
  }
}
