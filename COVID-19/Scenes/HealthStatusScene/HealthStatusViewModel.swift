//
//  HealthStatusViewModel.swift
//  COVID-19
//
//  Created by Ivan Georgiev on 19.03.20.
//  Copyright © 2020 Upnetix AD. All rights reserved.
//

import Foundation
import TwoWayBondage

class HealthStatusViewModel {
    
    typealias NoSymptomsCellConfigurator = BaseViewConfigurator<NoSymptomsTableViewCell>
    typealias QuestionCellConfigurator = BaseViewConfigurator<QuestionTableViewCell>
    typealias SubmitCellConfigurator = BaseViewConfigurator<SubmitTableViewCell>
    
    private var configurators: [ViewConfigurator] = []
    private var healthStatusData: HealthStatus?
    let shouldReloadData = Observable<Bool>()
    let isLeavingScreenAvailable = Observable<Bool>()
    let reloadCellIndexPath = Observable<IndexPath>()
    
    private var hasEmptyFields: Bool {
        guard let questions = healthStatusData?.questions else { return true }
        var hasEmpty = false
        for question in questions where question.questionState == nil {
            hasEmpty = true
            break
        }
        return hasEmpty
    }
    
    private var areAllFieldsNegative: Bool {
        guard let questions = healthStatusData?.questions else { return false }
        var areAllNegative = true
        for question in questions where question.questionState == true || question.questionState == nil {
            areAllNegative = false
            break
        }
        return areAllNegative
    }
    
    var numberOfCells: Int {
        return configurators.count
    }
    
    func viewConfigurator(at index: Int, in section: Int) -> ViewConfigurator? {
        return configurators[index]
    }
    
    private func didTapNoSymptomsButton(isActive: Bool) {

        (configurators[0] as? NoSymptomsCellConfigurator)?.data.hasSymptoms = isActive
        configurators.forEach { (configurator) in
            if let conf = configurator as? QuestionCellConfigurator {
                conf.data.isSymptomActive = isActive ? false : nil
                healthStatusData?.questions?[conf.data.index].questionState = isActive ? false : nil
//                reloadCellIndexPath.value = IndexPath(item: conf.data.index, section: 0)
            }
        }

        shouldReloadData.value = true
    }
    
    private func didTapSubmitButton() {
        isLeavingScreenAvailable.value = !hasEmptyFields
    }
    
    private func updateSymptoms(for index: Int, hasSymptoms: Bool) {
        healthStatusData?.questions?[index].questionState = hasSymptoms
        
        (configurators[0] as? NoSymptomsCellConfigurator)?.data.hasSymptoms = areAllFieldsNegative
        reloadCellIndexPath.value = IndexPath(item: 0, section: 0)
    }
    
    func getHealthStatusData() {
        if let url = Bundle.main.url(forResource: "HealthStatusJson", withExtension: "json") {
            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                let jsonData = try decoder.decode(HealthStatus.self, from: data)
                
                self.healthStatusData = jsonData
                
                configurators.append(NoSymptomsCellConfigurator(data:
                    NoSymptomsCellModel(hasSymptoms: jsonData.hasSymptoms ?? false,
                                        didTapCheckBox: { [weak self] isSelected in
                                            self?.didTapNoSymptomsButton(isActive: isSelected)
                    })))
                
                jsonData.questions?.enumerated().forEach { (question) in
                    configurators.append(QuestionCellConfigurator(data:
                        QuestionCellModel(index: question.offset,
                                          title: question.element.questionTitle,
                                          isSymptomActive: question.element.questionState,
                                          didTapButton: { [weak self] hasSymptoms in
                                            self?.updateSymptoms(for: question.offset,
                                                                 hasSymptoms: hasSymptoms)
                        })))
                }
                
                configurators.append(SubmitCellConfigurator(data: { [weak self] in
                    self?.didTapSubmitButton()
                }))

                shouldReloadData.value = true
            } catch {
                print("error:\(error)")
            }
        }
    }
    
}
