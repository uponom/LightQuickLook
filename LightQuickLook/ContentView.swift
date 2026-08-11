import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("LightQuickLook").font(.title2.weight(.semibold))
            Text("Native, private Quick Look previews with lightweight syntax highlighting.")
                .foregroundStyle(.secondary)
            Text("YAML · JSON · PowerShell · Bash · Terraform/HCL · Markdown")
                .font(.callout.monospaced())
            Divider()
            Text("Enable the extension in System Settings → General → Login Items & Extensions → Quick Look.")
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 520)
    }
}
