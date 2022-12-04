//
//  CarbInputView.swift
//  LoopCaregiver
//
//  Created by Bill Gestrich on 11/13/22.
//

import SwiftUI
import NightscoutClient

struct CarbInputView: View {
    
    var looperService: LooperService
    @Binding var showSheetView: Bool
    
    @State private var carbInput: String = ""
    @State private var foodType: String = "" //TODO: Pass This back to Loop for descriptive entries
    @State private var duration: String = "3" //TODO: Get Looper's default medium duration
    @State private var submissionInProgress = false
    @State private var isPresentingConfirm: Bool = false
    @State private var pickerConsumedDate: Date = Date()
    @State private var showDatePickerSheet: Bool = false
    @State private var showFoodEmojis: Bool = true
    @State private var errorText: String? = nil
    @State var foodTypeWidth = 160.0
    @FocusState private var carbInputViewIsFocused: Bool
    @FocusState private var durationInputFieldIsFocused: Bool
    
    private let minAbsorptionTimeInHours = 0.5
    private let maxAbsorptionTimeInHours = 8.0
    private let maxPastCarbEntryHours = 12
    private let maxFutureCarbEntryHours = 1
    private let unitFrameWidth: CGFloat = 20.0
    
    var body: some View {
        NavigationStack {
            ZStack {
                VStack {
                    carbEntryForm
                    if let errorText {
                        Text(errorText)
                            .foregroundColor(.critical)
                    }
                    Button("Deliver") {
                        deliverButtonTapped()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(disableForm())
                    .padding()
                    .confirmationDialog("Are you sure?",
                                        isPresented: $isPresentingConfirm) {
                        Button("Deliver \(carbInput)g of carbs to \(looperService.looper.name)?", role: .none) {
                            deliverConfirmationButtonTapped()
                        }
                        Button("Cancel", role: .cancel) {}
                    }
                }
                .disabled(submissionInProgress)
                if submissionInProgress {
                    ProgressView()
                }
            }
            .navigationBarTitle(Text("Add Carb Entry"), displayMode: .inline)
            .navigationBarItems(leading: Button(action: {
                self.showSheetView = false
            }) {
                Text("Cancel")
            })
            .sheet(isPresented: $showDatePickerSheet) {
                VStack {
                    Text("Consumption Date")
                        .font(.headline)
                        .padding()
                    Form {
                        DatePicker("Time", selection: $pickerConsumedDate, displayedComponents: [.hourAndMinute, .date])
                            .datePickerStyle(.automatic)
                    }
                }.presentationDetents([.fraction(1/4)])
            }
        }
    }
    
    var carbEntryForm: some View {
        Form {
            LabeledContent {
                TextField(
                    "0",
                    text: $carbInput
                )
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
                .focused($carbInputViewIsFocused)
                .onAppear(perform: {
                    carbInputViewIsFocused = true
                })
                Text("g")
                    .frame(width: unitFrameWidth)
            } label: {
                Text("Amount Consumed")
            }
            
            LabeledContent {
                Button {
                    showDatePickerSheet = true
                } label: {
                    Text(dateFormatter.string(from: pickerConsumedDate))
                }
            } label: {
                Text("Time")
            }

            //Auggie - absorption duration shortcuts per Loop timelines (0.5, 3, 5 hours)
            //TODO: can we get durations from Loop directly via .slow, .medium, .fast?
            //Create the "Food Type" row to hold emojis/typed description
            HStack {
                LabeledContent{
                    TextField("", text: $foodType)
                        .multilineTextAlignment(.trailing)
                        //Capture the user's tap to override emoji shortcut entries
                        //User can type in their own description (or go back to selecting emoji)
                        .onTapGesture {
                            showFoodEmojis = false
                            foodTypeWidth = .infinity
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                } label: {
                    Text("Food Type")
                }
                .frame(width: foodTypeWidth, height: 30, alignment: .trailing)
                Spacer()

                //Fast carb entry emoji
                if (showFoodEmojis) {
                    Button(action: {}) {
                        Text("🍭")
                    }
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .onTapGesture {
                        duration = "0.5"
                    }
                    Spacer()
                    
                    //Medium carb entry emoji
                    Button(action: {}) {
                        Text("🌮")
                    }
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .onTapGesture {
                        duration = "3"
                    }
                    Spacer()
                    
                    //Slow carb entry emoji
                    Button(action: {}) {
                        Text("🍕")
                    }
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .onTapGesture {
                        duration = "5"
                    }
                    Spacer()
                    
                    //Custom carb entry emoji, move focus to the duration input field
                    Button(action: {}) {
                        Text("🍽️")
                    }
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .onTapGesture {
                        duration = ""
                        durationInputFieldIsFocused = true
                    }
                }
            }
            
            LabeledContent {
                TextField(
                    "",
                    text: $duration
                )
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
                .focused($durationInputFieldIsFocused)
                Text("hr")
                    .frame(width: unitFrameWidth)
            } label: {
                Text("Absorption Time")
            }
        }
    }
    
    private func deliverButtonTapped() {
        carbInputViewIsFocused = false
        do {
            errorText = nil
            try validateForm()
            isPresentingConfirm = true
        } catch {
            errorText = error.localizedDescription
        }
    }
    
    @MainActor
    private func deliverConfirmationButtonTapped() {
        Task {
            submissionInProgress = true
            do {
                try await deliverCarbs()
                showSheetView = false
            } catch {
                errorText = error.localizedDescription
            }
            
            submissionInProgress = false
        }
    }
    
    private func deliverCarbs() async throws {
        let fieldValues = try getCarbFieldValues()
        let _ = try await looperService.remoteDataSource.deliverCarbs(amountInGrams: fieldValues.amountInGrams,
                                                                      durationInHours: Float(fieldValues.durationInHours), //TODO: Use double value in NS service
                                                                      consumedDate: fieldValues.consumedDate)
    }
    
    private func validateForm() throws {
        let _ = try getCarbFieldValues()
    }
    
    private func getCarbFieldValues() throws -> CarbInputViewFormValues {
        
        guard let carbAmountInGrams = Double(carbInput), carbAmountInGrams > 0, carbAmountInGrams <= 250 else { //TODO: Check Looper's max carb amount
            throw CarbInputViewError.invalidCarbAmount
        }
        
        guard let durationInHours = Double(duration), durationInHours >= minAbsorptionTimeInHours, durationInHours <= maxAbsorptionTimeInHours else {
            throw CarbInputViewError.invalidAbsorptionTime(minAbsorptionTimeInHours: minAbsorptionTimeInHours, maxAbsorptionTimeInHours: maxAbsorptionTimeInHours)
        }
        
        let now = Date()
        let consumedDate = pickerConsumedDate
        
        let oldestAcceptedDate = now.addingTimeInterval(-60 * 60 * Double(maxPastCarbEntryHours))
        let latestAcceptedDate = now.addingTimeInterval(60 * 60 * Double(maxFutureCarbEntryHours))
        
        guard consumedDate >= oldestAcceptedDate else {
            throw CarbInputViewError.exceedsMaxPastHours(maxPastHours: maxPastCarbEntryHours)
        }
        
        guard consumedDate <= latestAcceptedDate else {
            throw CarbInputViewError.exceedsMaxFutureHours(maxFutureHours: maxFutureCarbEntryHours)
        }
        
        return CarbInputViewFormValues(amountInGrams: carbAmountInGrams, durationInHours: durationInHours, consumedDate: consumedDate)
    }
    
    private func disableForm() -> Bool {
        return submissionInProgress || !carbInputFieldHasNumberValues() || !durationFieldHasNumberValues()
    }
    
    private func carbInputFieldHasNumberValues() -> Bool {
        return !carbInput.isEmpty && Double(carbInput) != nil
    }
    
    private func durationFieldHasNumberValues() -> Bool {
        return !duration.isEmpty && Float(duration) != nil
    }
    
    private var dateFormatter: DateFormatter {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short
        return dateFormatter
    }
    
}

struct CarbInputViewFormValues {
    let amountInGrams: Double
    let durationInHours: Double
    let consumedDate: Date
}

enum CarbInputViewError: LocalizedError {
    case invalidCarbAmount
    case invalidAbsorptionTime(minAbsorptionTimeInHours: Double, maxAbsorptionTimeInHours: Double)
    case exceedsMaxPastHours(maxPastHours: Int)
    case exceedsMaxFutureHours(maxFutureHours: Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidCarbAmount:
            return "Enter a carb amount between 1 and the max allowed in Loop Settings"
        case .invalidAbsorptionTime(let minAbsorptionTimeInHours, let maxAbsorptionTimeInHours):
            return "Enter a an absorption time between \(minAbsorptionTimeInHours) and \(maxAbsorptionTimeInHours) hours"
        case .exceedsMaxPastHours(let maxPastHours):
            return "Time must be within the prior \(maxPastHours) \(pluralizeHour(count: maxPastHours))"
        case .exceedsMaxFutureHours(let maxFutureHours):
            return "Time must be within the next \(maxFutureHours) \(pluralizeHour(count: maxFutureHours))"
        }
    }
    
    func pluralizeHour(count: Int) -> String {
        if count > 1 {
            return "hours"
        } else {
            return "hour"
        }
    }
}
