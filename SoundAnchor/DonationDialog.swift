import SwiftUI

struct DonationDialog: View {
    @Binding var isPresented: Bool
    let donationURL = URL(string: Bundle.main.object(forInfoDictionaryKey: "DonateURL") as? String ?? "")!
    
    var body: some View {
        VStack(spacing: 20) {
            Text("donation_title".localized)
                .font(.title2)
                .fontWeight(.bold)
            
            Text("donation_message".localized)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            HStack(spacing: 20) {
                Button("donation_cancel".localized) {
                    isPresented = false
                }
                .buttonStyle(.bordered)
                
                Link("donation_donate".localized, destination: donationURL)
                    .onTapGesture {
                        UserDefaults.standard.set(true, forKey: "hasDonated")
                    }
            }
        }
        .padding()
        .frame(width: 300)
        .background(Color(.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 5)
    }
} 
