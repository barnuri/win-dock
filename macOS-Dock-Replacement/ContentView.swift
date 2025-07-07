import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Text("Windows 11 Style Dock Replacement")
                .font(.title)
                .padding()
            Spacer()
            HStack {
                ForEach(0..<5) { index in
                    Button(action: {
                        print("App \(index) clicked")
                    }) {
                        Image(systemName: "app.fill")
                            .resizable()
                            .frame(width: 50, height: 50)
                            .padding()
                    }
                }
            }
            Spacer()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
