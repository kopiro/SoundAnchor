import SwiftUI
import FirebaseAnalytics

struct DonationReminderDialog: View {
    @Binding var isPresented: Bool
    let donationURL = URL(string: Bundle.main.object(forInfoDictionaryKey: "DonateURL") as? String ?? "")!
    
    var body: some View {
        VStack(spacing: 20) {
            Text("reminder_title".localized)
                .font(.title2)
                .fontWeight(.bold)
            
            Text("reminder_message".localized)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            HStack(spacing: 20) {
                Button("reminder_later".localized) {
                    UserDefaults.standard.set(Date(), forKey: "LastDonationReminder")
                    isPresented = false
                }
                .buttonStyle(.plain)
                
                Button("donation_donate".localized) {
                    UserDefaults.standard.set(true, forKey: "HasDonated")
                    Analytics.logEvent("donation_clicked", parameters: ["source": "reminder"])
                    isPresented = false
                    NSWorkspace.shared.open(donationURL)
                }
                .buttonStyle(.bordered)
                .accentColor(.accentColor)
            }
        }
        .padding()
        .frame(width: 300)
        .background(Color(.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 5)
    }
} 
