//
//  LanguagesViewModel.swift
//  COVID-19
//
//  Created by Gandi Pirkov on 30.03.20.
//  Copyright © 2020 Upnetix AD. All rights reserved.
//

import Foundation
import UpnetixLocalizer
import TwoWayBondage

final class LanguagesViewModel {

    var laguanges = Observable<[(String,String)]>()
    let shouldShowLoadingIndicator = Observable<Bool>()
    
    private let firstLaunchCheckRepository: AppLaunchRepository
    
    var isInitialFlow: Bool {
        return !firstLaunchCheckRepository.isAppLaunchedBefore
    }
    
    init(firstLaunchCheckRepository: AppLaunchRepository) {
        self.firstLaunchCheckRepository = firstLaunchCheckRepository
        getAvailableLanguages()
        
    }
    
    func getAvailableLanguages() {
        shouldShowLoadingIndicator.value = true
        Localizer.shared.getAvailableLocales { langauges, error in
            guard error == nil else {
                self.shouldShowLoadingIndicator.value = false
                return
                
            }
            
            var currentLanguages:[(String, String)] = []
            
            for language in langauges {
                currentLanguages.append((language.code, language.name))
            }
            
            self.laguanges.value = currentLanguages
            self.shouldShowLoadingIndicator.value = false
        }
    }
}