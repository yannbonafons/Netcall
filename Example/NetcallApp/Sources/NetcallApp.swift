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
    
    enum Request {
        case getList
        
        var requestInfo: NetCallRequestInfo {
            switch self {
            case .getList:
                .get(url: .fullURL("https://api.github.com/users/mralexgray/repos"))
            }
        }
    }

    func fetch() async throws -> String {
        let requestInfo = Request.getList.requestInfo
        return try await netcall.fetchRemoteData(requestInfo: requestInfo)
    }
}
