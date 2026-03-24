import SwiftUI

struct RecordRow: View {
    @Binding var isRec: Bool
    @Binding var val: (UInt16, UInt64)?
    let title: String
    var onToggle: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            
            HStack(spacing: 6) {
                Button(action: { isRec.toggle(); onToggle() }) {
                    Text(isRec ? NSLocalizedString("waiting.for.input", comment: "") : (val == nil ? NSLocalizedString("click.to.record", comment: "") : MyMap.getName(val!.0, val!.1)))
                        .font(.system(size: 11))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(isRec ? Color.red.opacity(0.1) : Color.blue.opacity(0.05))
                        .cornerRadius(4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(
                            isRec ? Color.red.opacity(0.5) : Color.blue.opacity(0.2)
                        ))
                }
                .buttonStyle(.plain)
                
                // 清除当前录入按钮
                if val != nil || isRec {
                    Button(action: { val = nil; isRec = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}