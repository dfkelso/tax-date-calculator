// app/javascript/controllers/ai_assistant_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["result", "spinner", "modal"]

    connect() {
        // Initialize modal
        this.modalTarget.style.display = 'none'
        console.log("AI Assistant controller connected:", this.element)
    }

    async generateRules(event) {
        event.preventDefault()
        console.log("Generate rules button clicked")
        this.spinnerTarget.style.display = 'block'
        this.resultTarget.innerHTML = ''
        this.modalTarget.style.display = 'block'

        // Get values from form inputs
        const formData = {
            form_number: document.getElementById('form_number').value,
            form_name: document.getElementById('form_name').value,
            entity_type: document.getElementById('entity_type').value,
            locality_type: document.getElementById('locality_type').value,
            locality: document.getElementById('locality').value
        }

        console.log("Form data:", formData)

        try {
            console.log("Sending request to:", '/admin/forms/generate_calculation_rules')
            const response = await fetch('/admin/forms/generate_calculation_rules', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').getAttribute('content')
                },
                body: JSON.stringify(formData)
            })

            console.log("Response status:", response.status)

            // Log raw response for debugging
            const responseText = await response.text()
            console.log("Raw response:", responseText)

            let data
            try {
                data = JSON.parse(responseText)
            } catch (e) {
                console.error("Error parsing JSON:", e)
                this.resultTarget.innerHTML = `<div class="error">Error parsing response: ${e.message}</div>`
                this.spinnerTarget.style.display = 'none'
                return
            }

            if (response.ok) {
                console.log("Parsed data:", data)
                this.displayResults(data)
            } else {
                this.resultTarget.innerHTML = `<div class="error">Error: ${data.error || 'Failed to generate calculation rules'}</div>`
            }
        } catch (error) {
            console.error("Fetch error:", error)
            this.resultTarget.innerHTML = `<div class="error">Error: ${error.message}</div>`
        } finally {
            this.spinnerTarget.style.display = 'none'
        }
    }

    displayResults(data) {
        console.log("Displaying results:", data)
        if (!data.calculationRules || data.calculationRules.length === 0) {
            this.resultTarget.innerHTML = '<div class="error">No calculation rules found</div>'
            return
        }

        // Sort rules by years (newest first)
        data.calculationRules.sort((a, b) => {
            return Math.max(...b.effectiveYears) - Math.max(...a.effectiveYears)
        })

        let html = '<div class="calculation-rules-preview">'
        html += '<h3>Generated Calculation Rules</h3>'

        data.calculationRules.forEach((rule, index) => {
            html += `
        <div class="rule-card">
          <div class="rule-card-header">
            <h4>Rule #${index + 1} - Years: ${rule.effectiveYears.join(', ')}</h4>
          </div>
          <div class="rule-card-body">
            <p><strong>Due Date:</strong> ${rule.dueDate.monthsAfterYearEnd} months after year end, day ${rule.dueDate.dayOfMonth}</p>
            
            ${rule.extensionDueDate ?
                `<p><strong>Extension Due Date:</strong> ${rule.extensionDueDate.monthsAfterYearEnd} months after year end, day ${rule.extensionDueDate.dayOfMonth}</p>` :
                '<p><strong>Extension Due Date:</strong> Not available</p>'
            }
            
            ${rule.dueDate.fiscalYearExceptions ?
                this.renderFiscalExceptions(rule.dueDate.fiscalYearExceptions) :
                ''
            }
          </div>
          <div class="rule-card-footer">
            <label class="checkbox-container">
              <input type="checkbox" class="rule-checkbox" data-rule-index="${index}" checked>
              <span class="checkbox-label">Include this rule</span>
            </label>
          </div>
        </div>
      `
        })

        html += `
      <div class="rule-actions">
        <button type="button" class="btn btn-primary" data-action="ai-assistant#applyRules">Apply Selected Rules</button>
        <button type="button" class="btn btn-secondary" data-action="ai-assistant#closeModal">Close</button>
      </div>
    </div>`

        this.resultTarget.innerHTML = html

        // Store the rules data for later use
        this.rulesData = data.calculationRules
        console.log("Rules data stored:", this.rulesData)
    }

    renderFiscalExceptions(exceptions) {
        let html = '<div class="fiscal-exceptions"><p><strong>Fiscal Year Exceptions:</strong></p><ul>'

        for (const [month, exception] of Object.entries(exceptions)) {
            html += `<li>Month ${month}: ${exception.monthsAfterYearEnd} months after year end, day ${exception.dayOfMonth}</li>`
        }

        html += '</ul></div>'
        return html
    }

    applyRules() {
        console.log("Apply rules button clicked")
        // Get selected rules
        const selectedRules = []
        document.querySelectorAll('.rule-checkbox:checked').forEach(checkbox => {
            const index = checkbox.dataset.ruleIndex
            selectedRules.push(this.rulesData[index])
        })

        console.log("Selected rules:", selectedRules)

        // Check if we're editing or creating
        const formId = window.location.pathname.match(/\/admin\/forms\/(\d+)\/edit/)
        console.log("Form ID match:", formId)

        if (formId) {
            // Update existing form
            this.updateExistingForm(formId[1], selectedRules)
        } else {
            // Add to new form
            this.addToNewForm(selectedRules)
        }

        this.closeModal()
    }

    updateExistingForm(formId, selectedRules) {
        console.log("Updating existing form:", formId)
        // Send an AJAX request to update the form
        fetch(`/admin/forms/${formId}/update_calculation_rules`, {
            method: 'PATCH',
            headers: {
                'Content-Type': 'application/json',
                'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').getAttribute('content')
            },
            body: JSON.stringify({ calculation_rules: selectedRules })
        })
            .then(response => response.json())
            .then(data => {
                console.log("Update response:", data)
                if (data.success) {
                    // Refresh the page to show updated rules
                    window.location.reload()
                } else {
                    alert('Failed to update calculation rules: ' + (data.error || 'Unknown error'))
                }
            })
            .catch(error => {
                console.error('Error:', error)
                alert('An error occurred while updating calculation rules')
            })
    }

    addToNewForm(selectedRules) {
        console.log("Adding to new form")
        // Create hidden inputs for each rule
        const container = document.createElement('div')
        container.id = 'calculation-rules-container'
        container.style.display = 'none'

        selectedRules.forEach((rule, i) => {
            const ruleJson = JSON.stringify(rule)
            const input = document.createElement('input')
            input.type = 'hidden'
            input.name = `calculation_rules[${i}]`
            input.value = ruleJson
            container.appendChild(input)
            console.log(`Added rule ${i}:`, ruleJson)
        })

        // Remove any existing rules container
        const existingContainer = document.getElementById('calculation-rules-container')
        if (existingContainer) {
            existingContainer.remove()
        }

        // Add the new container to the form
        const formElement = document.getElementById('formEditor')
        formElement.appendChild(container)
        console.log("Form with rules:", formElement)

        // Show success message
        alert('Calculation rules have been added to the form. Submit the form to save them.')
    }

    closeModal() {
        console.log("Closing modal")
        this.modalTarget.style.display = 'none'
    }
}