// app/javascript/controllers/confirm_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static values = {
        message: String,
        url: String,
        method: { type: String, default: 'delete' },
        redirectUrl: String
    }

    confirm(event) {
        event.preventDefault()

        if (confirm(this.messageValue)) {
            this.performRequest()
        }
    }

    performRequest() {
        const csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content")

        // Create and submit a hidden form
        const form = document.createElement('form')
        form.method = 'POST'
        form.action = this.urlValue
        form.style.display = 'none'

        // Add CSRF token
        const csrfInput = document.createElement('input')
        csrfInput.type = 'hidden'
        csrfInput.name = 'authenticity_token'
        csrfInput.value = csrfToken
        form.appendChild(csrfInput)

        // Add method override for DELETE, PUT, PATCH
        if (this.methodValue !== 'post') {
            const methodInput = document.createElement('input')
            methodInput.type = 'hidden'
            methodInput.name = '_method'
            methodInput.value = this.methodValue
            form.appendChild(methodInput)
        }

        // Add the form to the body and submit it
        document.body.appendChild(form)
        form.submit()
    }
}