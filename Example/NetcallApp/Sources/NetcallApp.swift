import SwiftUI
import Netcall

@main
struct NetcallApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Hello from Netcall 🎉")
        }
    }
}

struct NetcallView: View {
    @State private var name: String = ""
    
    var body: some View {
        Text(name)
            .task {
                await loadName()
            }
    }

    private func loadName() async {
        do {
            let service = NetcallService()
            name = try await service.fetch()
        } catch {
        }
    }
}

struct NetcallService {
    let netcall: NetCallClientProtocol
    
    init(netcall: NetCallClientProtocol = NetCallClient.shared) {
        self.netcall = netcall
    }
    
    func fetch() async throws -> String {
        let requestInfo = NetCallRequestInfo.get(urlString: "")
        return try await netcall.fetchRemoteData(requestInfo: requestInfo)
    }
}
