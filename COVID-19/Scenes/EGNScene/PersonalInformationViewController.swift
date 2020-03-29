//
//  PersonalInformationViewController.swift
//  COVID-19
//
//  Created by Gandi Pirkov on 27.03.20.
//  Copyright © 2020 Upnetix AD. All rights reserved.
//

import UIKit
import SkyFloatingLabelTextField
import IQKeyboardManager

enum Gender: String, Codable, CaseIterable {
    case male = "MALE"
    case female = "FEMALE"
    case other = "OTHER"
    case notSelected = ""

    var tag: Int {
        switch self {
        case .male:
            return 0
        case .female:
            return 1
        case .other:
            return 2
        case .notSelected:
            return 3
        }
    }
}

class PersonalInformationViewController: UIViewController, Navigateble {

    // MARK: Navigateble

    weak var navigationDelegate: NavigationDelegate?
    
    // MARK: Outlets
    
    @IBOutlet private weak var egnTitleLabel: UILabel!
    @IBOutlet private weak var iconImageView: UIImageView!
    @IBOutlet private weak var egnTextField: SkyFloatingLabelTextField!
    
    @IBOutlet weak var ageTextField: SkyFloatingLabelTextField!
    @IBOutlet private weak var egnSubmitButton: UIButton!
    @IBOutlet private weak var skipButton: UIButton!
    @IBOutlet private var genderButtons: [UIButton]!
    @IBOutlet weak var preexistingConditionsTextField: SkyFloatingLabelTextField!
    
    // MARK: Settings
    private let preexistingConditionsTextLength = 100 // Same as android
    private let maximumPersonalNumberLength = 20
    private let maximumAge = 110
    
    // MARK: View Model
    
    var viewModel: PersonalInformationViewModel!

    // MARK: Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        viewModel.start()
        setupUI()
        setupBindings()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        IQKeyboardManager.shared().keyboardDistanceFromTextField = 80
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        IQKeyboardManager.shared().keyboardDistanceFromTextField = 10
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        view.endEditing(true)
    }

    // MARK: Setup UI
    
    private func setupUI() {
        setupIconImageViewTint()
        setupEgnTextField()
        
        skipButton.isHidden = !viewModel.isInitialFlow
        
        title = viewModel.isInitialFlow == true ? Constants.Strings.mobileNumberVerificationТext :
                                                  Constants.Strings.generalPersonalInfoText
        
        egnSubmitButton.backgroundColor = .healthBlue
        egnTitleLabel.text = Constants.Strings.egnRequestText
        egnTextField.placeholder = Constants.Strings.egnRequestPlaceholderText
        ageTextField.placeholder = Constants.Strings.egnAgeText
        preexistingConditionsTextField.placeholder = Constants.Strings.egnPreexistingConditionsText
        egnSubmitButton.setTitle(Constants.Strings.egnSubmitText, for: .normal)
        skipButton.setTitle(Constants.Strings.egnSkipText, for: .normal)
    }
    
    private func setupIconImageViewTint() {
        let userShieldIcon = #imageLiteral(resourceName: "user-shield").withRenderingMode(.alwaysTemplate)
        iconImageView.image = userShieldIcon
        iconImageView.tintColor = .healthBlue
    }
    
    private func setupEgnTextField() {
        egnTextField.placeholder = Constants.Strings.egnRequestPlaceholderText + " "
        // By default title will be same as placeholder
        egnTextField.errorColor = .red
    }

    // MARK: Bind

    private func setupBindings() {
        viewModel.isSendPersonalInformationCompleted.bind { [weak self] result in
            self?.navigationDelegate?.navigateTo(step: .home)
            guard let strongSelf = self else { return }
            if !strongSelf.viewModel.isInitialFlow {
                strongSelf.navigationDelegate?.navigateTo(step: .home)
            }
            else {
                strongSelf.viewModel.didTapSkipButton()
            }
        }
        
        viewModel.shouldShowLoadingIndicator.bind { [weak self] shouldShowLoadingIndicator in
            guard let strongSelf = self else { return }
            if shouldShowLoadingIndicator {
                LoadingIndicatorManager.startActivityIndicator(.gray, in: strongSelf.view)
            } else {
                LoadingIndicatorManager.stopActivityIndicator(in: strongSelf.view)
            }
        }

        viewModel.requestError.bind { [weak self] error in
            switch error {
                case .invalidToken:
                    // TODO: Refactor - duplicated code
                    let alert = UIAlertController(title: Constants.Strings.invalidTokenAlertTitle,
                                                  message: Constants.Strings.invalidTokenAlertMessage,
                                                  preferredStyle: .alert)
                    alert.addAction(
                        UIAlertAction(title: Constants.Strings.genaralAgreedText, style: .default) { action in
                            self?.navigationDelegate?.navigateTo(step: .register)
                        }
                    )
                    self?.present(alert, animated: true, completion: nil)
                case .tooManyRequests(let repeatAfterSeconds):
                    var message = Constants.Strings.healthStatusTooManyRequestsErrorText + " "
                    let hours = repeatAfterSeconds / 3600
                    if hours > 0 {
                        message += ("\(hours) " + Constants.Strings.dateFormatHours)
                    }
                    let minutes = repeatAfterSeconds / 60
                    if minutes > 0 {
                        message += ("\(minutes) " + Constants.Strings.dateFormatMinutes)
                    }
                    if hours == 0 && minutes == 0 {
                        message += Constants.Strings.dateFormatLittleMoreTime
                    }
                    let alert = UIAlertController(title: nil,
                                                  message: message,
                                                  preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: Constants.Strings.genaralAgreedText,
                                                  style: .default,
                                                  handler: nil))
                    self?.present(alert, animated: true, completion: nil)
                case .server, .general:
                    self?.showToast(message: Constants.Strings.healthStatusUnknownErrorText)
            }
        }
        
        ageTextField.bind(with: viewModel.age)
        preexistingConditionsTextField.bind(with: viewModel.preexistingConditions)
        egnTextField.bind(with: viewModel.identificationNumber)
        viewModel.gender.bindAndFire { [weak self] value in
            guard let strongSelf = self else {
                return
            }
            
            for button in strongSelf.genderButtons {
                button.backgroundColor = .white
                button.setTitleColor(.healthBlue, for: .normal)
            }
            
            strongSelf.genderButtons[value.tag].setTitleColor(.white, for: .normal)
            strongSelf.genderButtons[value.tag].backgroundColor = .healthBlue
        }
  
        // fired only on success
        viewModel.isSendAnswersCompleted.bind { [weak self] result in
            self?.navigationDelegate?.navigateTo(step: .completed)
        }
    }
    
    // MARK: Actions
    
    @IBAction private func didTapSubmitButton(_ sender: Any) {
        var emptyTextFieldsTitles: [String] = []
        if (egnTextField.text ?? "").isEmpty {
            emptyTextFieldsTitles.append(Constants.Strings.egnRequestPlaceholderText)
        }
        if (ageTextField.text ?? "").isEmpty {
            emptyTextFieldsTitles.append(Constants.Strings.egnAgeText)
        }
        if (preexistingConditionsTextField.text ?? "").isEmpty {
            emptyTextFieldsTitles.append(Constants.Strings.egnPreexistingConditionsText)
        }

        if emptyTextFieldsTitles.isEmpty {
            viewModel.didTapPersonalNumberAuthorization(with: egnTextField.text ?? "")
        } else {
            let message = Constants.Strings.confirmEmptyFieldsAlertMessage + " " + emptyTextFieldsTitles.joined(separator: ", ")

            let alert = UIAlertController(title: nil,
                                          message: message,
                                          preferredStyle: .alert)
            alert.addAction(
                UIAlertAction(title: Constants.Strings.egnSkipText, style: .destructive) { [weak self] action in
                    self?.viewModel.didTapPersonalNumberAuthorization(with: self?.egnTextField.text ?? "")
                }
            )
            alert.addAction(
                UIAlertAction(title: Constants.Strings.generalBackText, style: .default) { _ in }
            )
            present(alert, animated: true, completion: nil)
        }
    }
    
    @IBAction private func didTapGenderButton(_ sender: UIButton) {
        viewModel.gender.value = Gender.allCases.first(where: { $0.tag == sender.tag }) ?? Gender.other
    }

    @IBAction private func didTapSkipButton(_ sender: Any) {
        viewModel.didTapSkipButton()
    }
    
}

// MARK: ToastViewPresentable

extension PersonalInformationViewController: ToastViewPresentable {}

// MARK: UITextFieldDelegate

extension PersonalInformationViewController: UITextFieldDelegate {
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        
        guard let textFieldText = textField.text as NSString? else { return false }
        let newString = textFieldText.replacingCharacters(in: range, with: string) as NSString
        
        if textField == egnTextField {
            return newString.length <= maximumPersonalNumberLength
        } else if textField == ageTextField {
            let newAge:Int = (newString as NSString).integerValue
            return newAge >= 0 && newAge <= maximumAge
        } else if textField ==  preexistingConditionsTextField{
            return newString.length <= preexistingConditionsTextLength
        }
        
        return true
    }
}