//
//  LoginView.swift
//  EhPanda
//
//  Created by 荒木辰造 on R 3/08/12.
//

import SwiftUI
import ComposableArchitecture

struct LoginView: View {
    private let store: Store<LoginState, LoginAction>
    @ObservedObject private var viewStore: ViewStore<LoginState, LoginAction>
    private let bypassesSNIFiltering: Bool
    private let blurRadius: Double

    @FocusState private var focusedField: LoginState.FocusedField?

    init(store: Store<LoginState, LoginAction>, bypassesSNIFiltering: Bool, blurRadius: Double) {
        self.store = store
        viewStore = ViewStore(store)
        self.bypassesSNIFiltering = bypassesSNIFiltering
        self.blurRadius = blurRadius
    }

    // MARK: LoginView
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Group {
                    WaveForm(color: Color(.systemGray2).opacity(0.2), amplify: 100, isReversed: true)
                    WaveForm(color: Color(.systemGray).opacity(0.2), amplify: 120, isReversed: false)
                }
                .offset(y: proxy.size.height * 0.3).drawingGroup()
                VStack(spacing: 15) {
                    Group {
                        LoginTextField(
                            focusedField: $focusedField, text: viewStore.binding(\.$username),
                            description: R.string.localizable.loginViewTitleUsername(), isPassword: false
                        )
                        LoginTextField(
                            focusedField: $focusedField, text: viewStore.binding(\.$password),
                            description: R.string.localizable.loginViewTitlePassword(), isPassword: true
                        )
                    }
                    .padding(.horizontal, proxy.size.width * 0.2)
                    Button {
                        viewStore.send(.login)
                    } label: {
                        Image(systemSymbol: .chevronForwardCircleFill)
                    }
                    .overlay { ProgressView().tint(nil).opacity(viewStore.loginState == .loading ? 1 : 0) }
                    .imageScale(.large).font(.largeTitle).foregroundColor(viewStore.loginButtonColor)
                    .disabled(viewStore.loginButtonDisabled).padding(.top, 30)
                }
            }
        }
        .synchronize(viewStore.binding(\.$focusedField), $focusedField)
        .sheet(unwrapping: viewStore.binding(\.$route), case: /LoginState.Route.webView) { route in
            WebView(url: route.wrappedValue) {
                viewStore.send(.loginDone(.success(nil)))
            }
            .autoBlur(radius: blurRadius)
        }
        .onSubmit { viewStore.send(.onTextFieldSubmitted) }
        .animation(.default, value: viewStore.loginState)
        .toolbar(content: toolbar)
        .navigationTitle(R.string.localizable.loginViewTitleLogin())
        .ignoresSafeArea()
    }
    // MARK: Toolbar
    private func toolbar() -> some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                viewStore.send(.setNavigation(.webView(Defaults.URL.webLogin)))
            } label: {
                Image(systemSymbol: .globe)
            }
            .disabled(bypassesSNIFiltering)
        }
    }
}

// MARK: LoginTextField
private struct LoginTextField: View {
    @Environment(\.colorScheme) private var colorScheme
    private let focusedField: FocusState<LoginState.FocusedField?>.Binding
    @Binding private var text: String
    private let description: String
    private let isPassword: Bool

    private var backgroundColor: Color {
        colorScheme == .light ? Color(.systemGray6) : Color(.systemGray5)
    }

    init(
        focusedField: FocusState<LoginState.FocusedField?>.Binding,
        text: Binding<String>, description: String, isPassword: Bool
    ) {
        self.focusedField = focusedField
        _text = text
        self.description = description
        self.isPassword = isPassword
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(description).font(.caption).foregroundStyle(.secondary)
            Group {
                if isPassword {
                    SecureField("", text: $text)
                } else {
                    TextField("", text: $text)
                }
            }
            .focused(focusedField.projectedValue, equals: isPassword ? .password : .username)
            .textContentType(isPassword ? .password : .username).submitLabel(isPassword ? .done : .next)
            .textInputAutocapitalization(.none).disableAutocorrection(true)
            .keyboardType(isPassword ? .asciiCapable : .default).padding(10)
            .background(backgroundColor.opacity(0.75).cornerRadius(8))
        }
    }
}

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            LoginView(
                store: .init(
                    initialState: .init(),
                    reducer: loginReducer,
                    environment: LoginEnvironment(
                        hapticClient: .live,
                        cookiesClient: .live
                    )
                ),
                bypassesSNIFiltering: false,
                blurRadius: 0
            )
        }
    }
}
