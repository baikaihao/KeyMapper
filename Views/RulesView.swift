import SwiftUI

struct RulesView: View {
    @StateObject var engine = MyEngine.shared
    @State private var tmpTrig: (UInt16, UInt64)?
    @State private var tmpTarg: (UInt16, UInt64)?
    @State private var tmpNote: String = ""
    @State private var isRec1 = false
    @State private var isRec2 = false
    @State private var editingNoteId: UUID? = nil
    @State private var editingNoteText: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            Text(NSLocalizedString("rules.title", comment: ""))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)
            
            ScrollView {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Text(NSLocalizedString("rules.original.key", comment: ""))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                        
                        Text(NSLocalizedString("rules.map.to", comment: ""))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                        
                        Text(NSLocalizedString("rules.note", comment: ""))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                        
                        Text(NSLocalizedString("rules.enable", comment: ""))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 60, alignment: .center)
                        
                        Text(NSLocalizedString("rules.actions", comment: ""))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 50, alignment: .center)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    
                    Divider()
                        .padding(.horizontal, 20)
                    
                    ForEach(Array(engine.list.enumerated()), id: \.element.id) { index, m in
                        HStack(spacing: 0) {
                            Text(MyMap.getName(m.fCode, m.fFlags))
                                .font(.system(size: 13, weight: .medium))
                                .frame(maxWidth: .infinity, alignment: .center)
                            
                            Text(MyMap.getName(m.tCode, m.tFlags))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.accentColor)
                                .frame(maxWidth: .infinity, alignment: .center)
                            
                            if editingNoteId == m.id {
                                TextField(NSLocalizedString("rules.note.placeholder", comment: ""), text: $editingNoteText)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12))
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(4)
                                    .background(Color(NSColor.textBackgroundColor))
                                    .cornerRadius(4)
                                    .onSubmit {
                                        saveNote(for: m.id)
                                    }
                                    .onExitCommand {
                                        editingNoteId = nil
                                    }
                            } else {
                                Text(m.note.isEmpty ? "-" : m.note)
                                    .font(.system(size: 12))
                                    .foregroundColor(m.note.isEmpty ? .secondary : .primary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .onTapGesture {
                                        editingNoteId = m.id
                                        editingNoteText = m.note
                                    }
                            }
                            
                            Toggle("", isOn: Binding(
                                get: { m.isOn },
                                set: { val in
                                    if let idx = engine.list.firstIndex(where: { $0.id == m.id }) {
                                        engine.list[idx].isOn = val
                                    }
                                }
                            ))
                            .toggleStyle(.switch)
                            .scaleEffect(0.7)
                            .labelsHidden()
                            .frame(width: 60, alignment: .center)
                            
                            Button(action: { engine.list.removeAll { $0.id == m.id } }) {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                            .frame(width: 50, alignment: .center)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(index % 2 == 1 ? Color.gray.opacity(0.1) : Color.clear)
                        .contentShape(Rectangle())
                        .onHover { isHovered in
                            if isHovered {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                    }
                    
                    Color.clear
                        .frame(height: 20)
                }
            }
            
            Divider()
            
            VStack(spacing: 12) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("rules.press.original", comment: ""))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        RecordBox(isRec: $isRec1, val: $tmpTrig) {
                            if isRec1 { isRec2 = false }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .padding(.top, 16)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("rules.map.as", comment: ""))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        RecordBox(isRec: $isRec2, val: $tmpTarg) {
                            if isRec2 { isRec1 = false }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .padding(.top, 16)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("rules.note", comment: ""))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        TextField(NSLocalizedString("rules.note.placeholder", comment: ""), text: $tmpNote)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                    }
                }
                
                Button(action: addMapping) {
                    Text(NSLocalizedString("rules.save", comment: ""))
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(tmpTrig == nil || tmpTarg == nil)
            }
            .padding(20)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .background(KeyLogic(r1: $isRec1, r2: $isRec2, t1: $tmpTrig, t2: $tmpTarg))
        .onChange(of: isRec1) { _ in engine.isRecording = isRec1 || isRec2 }
        .onChange(of: isRec2) { _ in engine.isRecording = isRec1 || isRec2 }
    }
    
    func addMapping() {
        if let a = tmpTrig, let b = tmpTarg {
            engine.list.append(MyMap(fCode: a.0, fFlags: a.1, tCode: b.0, tFlags: b.1, note: tmpNote))
            tmpTrig = nil
            tmpTarg = nil
            tmpNote = ""
        }
    }
    
    func saveNote(for id: UUID) {
        if let idx = engine.list.firstIndex(where: { $0.id == id }) {
            engine.list[idx].note = editingNoteText
        }
        editingNoteId = nil
    }
}

struct RecordBox: View {
    @Binding var isRec: Bool
    @Binding var val: (UInt16, UInt64)?
    var onToggle: () -> Void
    
    var body: some View {
        HStack {
            if isRec {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12, height: 12)
                Text(NSLocalizedString("rules.recording", comment: ""))
                    .font(.system(size: 12))
                    .foregroundColor(.accentColor)
            } else if let v = val {
                Text(MyMap.getName(v.0, v.1))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.accentColor)
            } else {
                Text(NSLocalizedString("rules.click.record", comment: ""))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    isRec ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 2])
                )
        )
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isRec ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            isRec.toggle()
            onToggle()
        }
    }
}
