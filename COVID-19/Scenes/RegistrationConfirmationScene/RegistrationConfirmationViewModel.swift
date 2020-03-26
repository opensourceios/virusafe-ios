//
//  RegistrationConfirmationViewModel.swift
//  COVID-19
//
//  Created by Ivan Georgiev on 20.03.20.
//  Copyright © 2020 Upnetix AD. All rights reserved.
//

import Foundation
import TwoWayBondage

class RegistrationConfirmationViewModel {
    
    let repository: RegistrationRepository
    let shouldShowLoadingIndicator = Observable<Bool>()
    let isRequestSuccessful = Observable<Bool>()

    init(repository: RegistrationRepository) {
        self.repository = repository
    }
    
    func didTapCodeAuthorization(with authorisationCode: String) {
        shouldShowLoadingIndicator.value = true
        repository.authoriseVerificationCode(verificationCode: authorisationCode) { [weak self] (success) in
            guard let strongSelf = self else { return }
            strongSelf.isRequestSuccessful.value = success
            strongSelf.shouldShowLoadingIndicator.value = false
        }
    }

    func mobileNumber() -> String {
        // TODO: Format phone if needed
        return repository.authorisedMobileNumber ?? "(+359) XXX-XXX"
    }
    
}
