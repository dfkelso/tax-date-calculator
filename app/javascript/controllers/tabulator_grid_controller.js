// app/javascript/controllers/tabulator_grid_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["table"]
    static values = {
        url: String,
        ajaxParams: Object,
        columns: Array,
        pagination: { type: Boolean, default: true },
        paginationSize: { type: Number, default: 10 },
        height: { type: String, default: "400px" },
        layout: { type: String, default: "fitColumns" },
        movableColumns: { type: Boolean, default: true },
        responsiveLayout: { type: String, default: "collapse" },
        initialSort: Array
    }

    connect() {
        this.loadTabulatorLibrary().then(() => {
            this.initializeTabulator()
        })
    }

    loadTabulatorLibrary() {
        return new Promise((resolve) => {
            // Check if Tabulator is already loaded
            if (window.Tabulator) {
                resolve()
                return
            }

            // Load Tabulator CSS
            const styleLink = document.createElement('link')
            styleLink.rel = 'stylesheet'
            styleLink.href = 'https://cdn.jsdelivr.net/npm/tabulator-tables@5.4.3/dist/css/tabulator.min.css'
            document.head.appendChild(styleLink)

            // Load Tabulator JS
            const script = document.createElement('script')
            script.src = 'https://cdn.jsdelivr.net/npm/tabulator-tables@5.4.3/dist/js/tabulator.min.js'
            script.onload = resolve
            document.head.appendChild(script)
        })
    }

    initializeTabulator() {
        // Parse custom column definitions from HTML data attribute if present
        const columns = this.hasColumnsValue ? this.columnsValue : this.generateColumnsFromTable()

        // Define our table configuration
        const config = {
            height: this.heightValue,
            layout: this.layoutValue,
            pagination: this.paginationValue,
            paginationSize: this.paginationSizeValue,
            movableColumns: this.movableColumnsValue,
            responsiveLayout: this.responsiveLayoutValue,
            ajaxURL: this.hasUrlValue ? this.urlValue : null,
            ajaxParams: this.hasAjaxParamsValue ? this.ajaxParamsValue : {},
            columns: columns,
            initialSort: this.hasInitialSortValue ? this.initialSortValue : []
        }

        // Create the Tabulator instance
        this.tabulatorTable = new Tabulator(this.tableTarget, config)

        // Set up event handlers
        this.tabulatorTable.on("cellEdited", (cell) => {
            this.handleCellEdited(cell)
        })

        this.tabulatorTable.on("rowClick", (e, row) => {
            this.handleRowClick(e, row)
        })
    }

    generateColumnsFromTable() {
        // If no columns defined, attempt to detect them from the table structure
        const columns = []

        // Check if there's a thead with th elements
        const headerRow = this.tableTarget.querySelector('thead tr')
        if (headerRow) {
            const headerCells = headerRow.querySelectorAll('th')
            headerCells.forEach(cell => {
                const field = cell.dataset.field || this.kebabToCamel(cell.textContent.trim().toLowerCase().replace(/\s+/g, '-'))
                columns.push({
                    title: cell.textContent.trim(),
                    field: field,
                    sorter: cell.dataset.sorter || "string",
                    headerFilter: cell.dataset.filter !== "false",
                    editor: cell.dataset.editable === "true" ? "input" : false
                })
            })
        }

        return columns
    }

    handleCellEdited(cell) {
        const row = cell.getRow()
        const data = row.getData()
        const rowId = data.id

        if (rowId && this.hasUrlValue) {
            // Prepare the data to send to the server
            const updateData = {
                [cell.getColumn().getField()]: cell.getValue()
            }

            // Send the data to the server
            fetch(`${this.urlValue}/${rowId}`, {
                method: 'PATCH',
                headers: {
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': this.getMetaValue('csrf-token')
                },
                body: JSON.stringify({ form: updateData })
            })
                .catch(error => {
                    console.error('Error updating data:', error)
                    // Revert the cell to its previous value on error
                    cell.restoreOldValue()
                })
        }
    }

    handleRowClick(e, row) {
        // Get the data for the clicked row
        const data = row.getData()

        // Emit a custom event with the row data
        const event = new CustomEvent('tabulator:rowClick', {
            bubbles: true,
            detail: { row: data }
        })
        this.element.dispatchEvent(event)

        // If the click is not on a cell with an editor, and the row has an ID
        if (e.target.tagName !== 'INPUT' && data.id) {
            // Optionally navigate to the form's show or edit page
            // Uncomment the line below to enable automatic navigation
            // window.location.href = `${this.urlValue}/${data.id}/edit`
        }
    }

    // Helpers
    kebabToCamel(string) {
        return string.replace(/-([a-z])/g, function(g) { return g[1].toUpperCase(); })
    }

    getMetaValue(name) {
        const element = document.head.querySelector(`meta[name="${name}"]`)
        return element ? element.getAttribute("content") : null
    }

    // Actions
    refresh() {
        if (this.tabulatorTable) {
            this.tabulatorTable.replaceData()
        }
    }

    download(event) {
        const type = event.params.type || "csv"
        const filename = event.params.filename || "table-export"

        if (this.tabulatorTable) {
            this.tabulatorTable.download(type, `${filename}.${type}`)
        }
    }

    filter(event) {
        const field = event.params.field
        const value = event.target.value

        if (this.tabulatorTable && field) {
            if (value === "") {
                this.tabulatorTable.clearFilter()
            } else {
                this.tabulatorTable.setFilter(field, "like", value)
            }
        }
    }
}