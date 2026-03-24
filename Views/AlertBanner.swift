import SwiftUI

struct AlertBanner: View {
    let message: String
    
    var body: some View {
        Text(message)
            .font(.caption)
            .foregroundColor(.yellow)
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .background(Color.yellow.opacity(0.2))
            .cornerRadius(5)
    }
}