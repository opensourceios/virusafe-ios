//
//  RegistrationConfirmationViewController.swift
//  COVID-19
//
//  Created by Ivan Georgiev on 20.03.20.
//  Copyright © 2020 Upnetix AD. All rights reserved.
//

import UIKit
import SkyFloatingLabelTextField
import IQKeyboardManager

class RegistrationConfirmationViewController: UIViewController, Navigateble {

    // MARK: Navigateble

    weak var navigationDelegate: NavigationDelegate?

    // MARK: Outlets
    
    @IBOutlet private weak var iconImageView: UIImageView!
    @IBOutlet private weak var textLabel: UILabel!
    @IBOutlet private weak var mobileNumberLabel: UILabel!
    @IBOutlet private weak var verificationCodeTextField: SkyFloatingLabelTextField!
    @IBOutlet private weak var errorLabel: UILabel!
    @IBOutlet private weak var confirmButton: UIButton!
    @IBOutlet private weak var noCodeReceivedButton: UIButton!
    
    
    // MARK: Settings

    private let maximumValidationCodeLength = 6

    // MARK: View Model

    // Injected from parent in order to get its instance of the RegistrationRepository
    var viewModel: RegistrationConfirmationViewModel!

    // MARK: Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupBindings()
        mobileNumberLabel.text = Constants.Strings.mobileNumberLabelТext +
        ": " + viewModel.mobileNumber()
        textLabel.text = Constants.Strings.mobileNumberIndentificationLabelТext
        noCodeReceivedButton.setTitle(Constants.Strings.mobileNumberNoCodeReceivedButton, for: .normal)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        IQKeyboardManager.shared().keyboardDistanceFromTextField = 80
        IQKeyboardManager.shared().isEnableAutoToolbar = false
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        IQKeyboardManager.shared().keyboardDistanceFromTextField = 10
        IQKeyboardManager.shared().isEnableAutoToolbar = true
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        view.endEditing(true)
    }

    // MARK: Setup UI

    private func setupUI() {
        title = Constants.Strings.mobileNumberVerificationТext
        confirmButton.backgroundColor = .healthBlue
        setupIconImageViewTint()
        setupVerificationCodeTextField()
    }

    private func setupIconImageViewTint() {
        let userShieldIcon = #imageLiteral(resourceName: "user-shield").withRenderingMode(.alwaysTemplate)
        iconImageView.image = userShieldIcon
        iconImageView.tintColor = .healthBlue
    }

    private func setupVerificationCodeTextField() {
        verificationCodeTextField.borderStyle = .none
        verificationCodeTextField.placeholder = Constants.Strings.mobileNumberEnterPinText + " "
        // By default title will be same as placeholder
        verificationCodeTextField.errorColor = .red
        // !!! other styles are in stotyboard
    }

    private func setupBindings() {
        viewModel.shouldShowLoadingIndicator.bind { [weak self] shouldShowLoadingIndicator in
            guard let strongSelf = self else { return }
            if shouldShowLoadingIndicator {
                strongSelf.verificationCodeTextField.resignFirstResponder()
                LoadingIndicatorManager.startActivityIndicator(.whiteLarge,
                                                               in: strongSelf.view)
            } else {
                LoadingIndicatorManager.stopActivityIndicator(in: strongSelf.view)
            }
        }

        viewModel.isCodeAuthorizationRequestSuccessful.bind { [weak self] result in
            guard let strongSelf = self else { return }
            switch result {
                case .success:
                    strongSelf.navigateToNextViewController()
                case .invalidPhoneNumber:
                    strongSelf.showToast(message: Constants.Strings.mobileNumberErrorWrongPinText)
                default:
                    strongSelf.showToast(message: Constants.Strings.registrationScreenGeneralErrorText)
            }
        }

        viewModel.isResendCodeRequestSuccessful.bind { [weak self] result in
            guard let strongSelf = self else { return }
            switch result {
                case .success:
                    strongSelf.showToast(message: Constants.Strings.mobileNumberSuccessfulPinText)
                case .invalidPhoneNumber:
                    strongSelf.showToast(message: Constants.Strings.registrationScreenInvalindNumberErrorText)
                default:
                    strongSelf.showToast(message: Constants.Strings.registrationScreenGeneralErrorText)
            }
        }

    }

    // MARK: Navigation

    private func navigateToNextViewController() {
        navigationDelegate?.navigateTo(step: viewModel.isInitialFlow ? .healthStatus : .home)
    }

    // MARK: Actions

    @IBAction private func resetCodeButtonDidTap (_ sender: Any) {
        viewModel.didTapResetCodeButton()
    }
    
    @IBAction private func didTapConfirmButton(_ sender: Any) {
        guard let authorizationCode = verificationCodeTextField.text else { return }

        if authorizationCode.count < 6 {
            errorLabel.isHidden = false
            errorLabel.text = Constants.Strings.mobileNumberIncorrectLengthText
            return
        } else if !authorizationCode.isDigitsOnly {
            errorLabel.isHidden = false
            errorLabel.text = Constants.Strings.generalErrorIncorrectFormatText
            return
        } else {
            errorLabel.isHidden = true
            viewModel.didTapCodeAuthorization(with: authorizationCode)
        }
    }
    
}

// MARK: UITextFieldDelegate

extension RegistrationConfirmationViewController: UITextFieldDelegate {
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard let textFieldText = textField.text as NSString? else { return false }
        let newString = textFieldText.replacingCharacters(in: range, with: string) as NSString
        
        return newString.length <= maximumValidationCodeLength
    }
}

// MARK: ToastViewPresentable

extension RegistrationConfirmationViewController: ToastViewPresentable {}

