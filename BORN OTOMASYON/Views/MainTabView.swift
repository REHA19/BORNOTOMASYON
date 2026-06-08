import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Menu item definition

private struct MenuItem: Identifiable {
    let tag:   Int
    var id:    Int { tag }
    let title: String
    let icon:  String
    let color: Color
}

private let allMenuItems: [MenuItem] = [
    MenuItem(tag: 0,  title: "Stok",         icon: "shippingbox.fill",                color: .blue),
    MenuItem(tag: 1,  title: "Hareket",      icon: "arrow.down.circle.fill",          color: .green),
    MenuItem(tag: 3,  title: "Sarfiyat",     icon: "chart.bar.xaxis",                 color: .orange),
    MenuItem(tag: 4,  title: "Ürt. Cetveli", icon: "tablecells.fill",                 color: .cyan),
    MenuItem(tag: 6,  title: "Uyarılar",     icon: "bell.fill",                       color: .red),
    MenuItem(tag: 7,  title: "Satın Alma",   icon: "cart.fill",                       color: Color(.systemBrown)),
    MenuItem(tag: 8,  title: "Hammadde",     icon: "square.3.layers.3d.down.forward", color: .teal),
    MenuItem(tag: 9,  title: "SingleBlend",  icon: "flask.fill",                      color: .mint),
    MenuItem(tag: 10, title: "Ayarlar",      icon: "gearshape.fill",                  color: .gray),
    MenuItem(tag: 11, title: "Rasyon Aktar", icon: "square.and.arrow.down.on.square", color: .indigo),
    MenuItem(tag: 12, title: "Şablonlar",    icon: "doc.badge.gearshape",             color: .purple),
    MenuItem(tag: 13, title: "MultiBlend",   icon: "rectangle.3.group.fill",          color: .indigo),
    MenuItem(tag: 14, title: "Gönderilen",   icon: "paperplane.fill",                 color: .orange),
    MenuItem(tag: 15, title: "Yem Rapor",    icon: "doc.text.fill",                   color: .green),
    MenuItem(tag: 16, title: "LP Analizi",   icon: "waveform.path.ecg.rectangle.fill", color: .purple),
    MenuItem(tag: 17, title: "Maliyet",     icon: "chart.bar.doc.horizontal.fill",    color: .yellow),
]

@ViewBuilder
private func destinationView(for tag: Int) -> some View {
    switch tag {
    case 0:  MaterialListView()
    case 1:  StockReportView()
    case 3:  ConsumptionView()
    case 4:  ProductionScheduleView()
    case 6:  NotificationsView()
    case 7:  PurchaseAlertView()
    case 8:  IngredientImportView()
    case 9:  SingleBlendListView()
    case 10: SettingsView()
    case 11: RasyonImportView()
    case 12: FormulaTemplateListView()
    case 13: MultiBlendListView()
    case 14: SentFormulasView()
    case 15: FeedReportView()
    case 16: LPAnalysisMenuView()
    case 17: MaliyetlendirmeView()
    default: MaterialListView()
    }
}

// MARK: - MainTabView

struct MainTabView: View {
    @StateObject private var formulaListVM = FormulaListViewModel()
    @AppStorage("textSizeStep") private var textSizeStep: Int = 1

    private var appDynamicTypeSize: DynamicTypeSize {
        [DynamicTypeSize.medium, .large, .xLarge, .xxLarge, .xxxLarge][max(0, min(4, textSizeStep))]
    }

    var body: some View {
        NavigationStack {
            MenuGridView(formulaListVM: formulaListVM)
        }
        .dynamicTypeSize(appDynamicTypeSize)
        .keyboardDismissToolbar()
    }
}

// MARK: - Keyboard dismiss toolbar (global)

extension View {
    /// Klavye açıkken üst çubuğa "klavyeyi kapat" butonu ekler.
    /// NavigationStack üzerinden tüm alt view'lara yayılır; sheet içindeki
    /// NavigationStack'lere de aynı modifier eklenebilir.
    func keyboardDismissToolbar() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Grid menu view

struct MenuGridView: View {
    let formulaListVM: FormulaListViewModel

    @Environment(\.horizontalSizeClass) private var sizeClass

    @AppStorage("appColorScheme")  private var colorSchemeStr: String = "system"
    @AppStorage("menuItemOrder")   private var savedOrder:     String = ""
    @AppStorage("textSizeStep")    private var textSizeStep:   Int    = 1

    @Query(filter: #Predicate<FeedIngredient> { $0.isAvailable == false })
    private var unavailableIngredients: [FeedIngredient]
    @Query private var allFormulas: [BlendFormula]

    @State private var orderedTags:  [Int]  = []
    @State private var editMode:     Bool   = false
    @State private var draggingTag:  Int?   = nil
    @State private var navTag:       Int?   = nil   // lazy navigation target

    // "Uyarılar" kartında gösterilecek rozet: formüllerde aktif ama stokta olmayan hammadde sayısı
    private var alertBadgeCount: Int {
        guard !unavailableIngredients.isEmpty else { return 0 }
        let unavailCodes: Set<String> = Set(unavailableIngredients.map { $0.code })
        let usedCodes: Set<String> = allFormulas.reduce(into: []) { result, formula in
            formula.ingredients.forEach { if $0.isActive { result.insert($0.code) } }
        }
        return unavailCodes.intersection(usedCodes).count
    }

    // Büyük boyutlarda sütun sayısını azalt ki kartlar sıkışmasın
    private var columns: [GridItem] {
        let base  = sizeClass == .regular ? 4 : 3
        let count = textSizeStep >= 3 ? max(2, base - 1) : base
        let gap   = textSizeStep >= 2 ? 10 : 16
        return Array(repeating: GridItem(.flexible(), spacing: CGFloat(gap)), count: count)
    }

    // Ordered list of MenuItems, filling in any new items at the end
    private var orderedItems: [MenuItem] {
        let allTags = allMenuItems.map { $0.tag }
        let valid   = orderedTags.filter { allTags.contains($0) }
        let missing = allTags.filter { !valid.contains($0) }
        return (valid + missing).compactMap { tag in allMenuItems.first { $0.tag == tag } }
    }

    // MARK: - Theme helpers

    private var themeIcon: String {
        switch colorSchemeStr {
        case "light": return "sun.max.fill"
        case "dark":  return "moon.fill"
        default:      return "circle.lefthalf.filled"
        }
    }

    private func cycleTheme() {
        switch colorSchemeStr {
        case "system": colorSchemeStr = "light"
        case "light":  colorSchemeStr = "dark"
        default:       colorSchemeStr = "system"
        }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            // Header
            ZStack(alignment: .topTrailing) {
                Image("BornLogo")
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .rotationEffect(.degrees(-90))
                    .frame(maxWidth: .infinity, maxHeight: sizeClass == .regular ? 220 : 130)
                    .padding(.horizontal, sizeClass == .regular ? 0 : 20)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                HStack(spacing: 6) {
                    if editMode {
                        Button("Bitti") {
                            withAnimation(.spring(duration: 0.3)) { editMode = false }
                        }
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(Color.blue.opacity(0.8))
                                .shadow(color: .blue.opacity(0.6), radius: 8)
                        )
                    }

                    Button(action: cycleTheme) {
                        Image(systemName: themeIcon)
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.top, 8)
                .padding(.trailing, 4)
            }

            // Grid
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(orderedItems) { item in
                    MenuGridCell(
                        item:        item,
                        badgeCount:  item.tag == 6 ? alertBadgeCount : 0,
                        editMode:    $editMode,
                        draggingTag: $draggingTag,
                        orderedTags: $orderedTags,
                        navTag:      $navTag
                    )
                }
            }
            .padding(16)

            if editMode {
                Text("Kartları basılı tutup sürükleyerek yeniden sıralayın")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 12)
            }
        }
        .scrollDisabled(editMode)
        .background(MenuBackground())
        .navigationBarHidden(true)
        // Destination view is created ONLY when user taps — not at grid render time
        .navigationDestination(item: $navTag) { tag in
            destinationView(for: tag)
        }
        .onAppear { initOrder() }
        .onChange(of: orderedTags) { _, newTags in
            savedOrder = newTags.map { "\($0)" }.joined(separator: ",")
        }
    }

    // MARK: - Order persistence

    private func initOrder() {
        let saved = savedOrder
            .split(separator: ",")
            .compactMap { Int($0) }
        orderedTags = saved.isEmpty ? allMenuItems.map { $0.tag } : saved
    }
}

// MARK: - Grid cell (separates normal-mode tap/longpress from edit-mode drag)

private struct MenuGridCell: View {
    let item:        MenuItem
    var badgeCount:  Int = 0
    @Binding var editMode:    Bool
    @Binding var draggingTag: Int?
    @Binding var orderedTags: [Int]
    @Binding var navTag:      Int?   // nil → navigates when set

    @State private var longPressDidFire = false

    var body: some View {
        if editMode {
            MenuCard(item: item, badgeCount: 0, editMode: true, isDragging: draggingTag == item.tag)
                .contentShape(Rectangle())
                .onDrag {
                    draggingTag = item.tag
                    return NSItemProvider(object: "\(item.tag)" as NSString)
                }
                .onDrop(
                    of: [UTType.plainText],
                    delegate: GridDropDelegate(
                        targetTag:   item.tag,
                        orderedTags: $orderedTags,
                        draggingTag: $draggingTag
                    )
                )
        } else {
            MenuCard(item: item, badgeCount: badgeCount, editMode: false, isDragging: false)
                .contentShape(Rectangle())
                .onTapGesture {
                    if longPressDidFire {
                        longPressDidFire = false
                    } else {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            navTag = item.tag   // lazy: destination only built now
                        }
                    }
                }
                .onLongPressGesture(minimumDuration: 0.45) {
                    longPressDidFire = true
                    withAnimation(.spring(duration: 0.3)) { editMode = true }
                }
        }
    }
}

// MARK: - Drop delegate

private struct GridDropDelegate: DropDelegate {
    let targetTag:   Int
    @Binding var orderedTags:  [Int]
    @Binding var draggingTag:  Int?

    func dropEntered(info: DropInfo) {
        guard let from = draggingTag,
              from != targetTag,
              let fromIdx = orderedTags.firstIndex(of: from),
              let toIdx   = orderedTags.firstIndex(of: targetTag),
              fromIdx != toIdx                           // already in place — skip
        else { return }

        withAnimation(.easeInOut(duration: 0.18)) {
            orderedTags.move(
                fromOffsets: IndexSet(integer: fromIdx),
                toOffset:    toIdx > fromIdx ? toIdx + 1 : toIdx
            )
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingTag = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

// MARK: - Single card (with self-contained wobble animation)

private struct MenuCard: View {
    let item:       MenuItem
    var badgeCount: Int = 0
    let editMode:   Bool
    let isDragging: Bool

    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("textSizeStep") private var textSizeStep: Int = 1
    @State private var rotAngle: Double = 0

    private static let scaleFactors: [CGFloat] = [0.75, 1.0, 1.2, 1.45, 1.7]
    private var scale: CGFloat { Self.scaleFactors[max(0, min(4, textSizeStep))] }

    // iPad / Mac → daha büyük kart elemanları, textSizeStep ile scale edilir
    private var iconSize:     CGFloat { (sizeClass == .regular ? 36 : 28)  * scale }
    private var iconFrame:    CGFloat { (sizeClass == .regular ? 64 : 52)  * scale }
    private var iconRadius:   CGFloat { (sizeClass == .regular ? 16 : 13)  * scale }
    private var vertPad:      CGFloat { (sizeClass == .regular ? 22 : 14)  * scale }
    private var cardRadius:   CGFloat { (sizeClass == .regular ? 24 : 20)  * scale }
    private var titleFont:    Font    { sizeClass == .regular ? .subheadline.bold() : .caption.bold() }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Dark card base with subtle color tint
            RoundedRectangle(cornerRadius: cardRadius)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.75),
                            item.color.opacity(0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint:   .bottomTrailing
                    )
                )

            // Neon border line
            RoundedRectangle(cornerRadius: cardRadius)
                .stroke(item.color.opacity(0.85), lineWidth: 1.5)

            // Content
            VStack(spacing: 10) {
                Image(systemName: item.icon)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: iconFrame, height: iconFrame)
                    .background(item.color.gradient, in: RoundedRectangle(cornerRadius: iconRadius))
                    .shadow(color: item.color.opacity(0.8), radius: 8, y: 2)

                Text(item.title)
                    .font(titleFont)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, vertPad)

            // Bildirim rozeti (sadece normal modda ve sayı > 0 ise)
            if !editMode && badgeCount > 0 {
                Text(badgeCount > 99 ? "99+" : "\(badgeCount)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.red, in: Capsule())
                    .padding(6)
            }

            // Edit mode handle
            if editMode {
                Image(systemName: "line.3.horizontal")
                    .font(.caption2.bold())
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(5)
            }
        }
        // Outer glow emanating from the border
        .shadow(color: item.color.opacity(0.55), radius: 10)
        .shadow(color: item.color.opacity(0.20), radius: 22)
        .rotationEffect(.degrees(isDragging ? 0 : rotAngle))
        .scaleEffect(isDragging ? 1.08 : 1.0)
        .opacity(isDragging ? 0.7 : 1.0)
        .onChange(of: editMode) { _, active in
            if active {
                rotAngle = -1.5
                withAnimation(.easeInOut(duration: 0.18).repeatForever(autoreverses: true)) {
                    rotAngle = 1.5
                }
            } else {
                withAnimation(.spring(duration: 0.25)) {
                    rotAngle = 0
                }
            }
        }
    }
}

// MARK: - Background

private struct MenuBackground: View {
    var body: some View {
        ZStack {
            // Deep dark navy base
            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.04, blue: 0.13),
                    Color(red: 0.04, green: 0.07, blue: 0.18)
                ],
                startPoint: .top,
                endPoint:   .bottom
            )

            // Subtle center radial highlight
            RadialGradient(
                colors: [
                    Color(red: 0.05, green: 0.20, blue: 0.50).opacity(0.30),
                    Color.clear
                ],
                center:      .top,
                startRadius: 0,
                endRadius:   500
            )
        }
        .ignoresSafeArea()
    }
}
