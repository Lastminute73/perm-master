import { LightningElement, api, track } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';

export default class AutoResizeTextarea extends LightningElement {
    @api label;
    @api placeholder;
    @api required = false;
    @api maxLength = 10000; // Default to 255 characters

    @track _internalValue = '';
    @track hasError = false;
    @track isFocused = false;

    @api
    get value() {
        return this._internalValue;
    }
    set value(val) {
        this._internalValue = val || '';
    }

    // Creates the "0 / 255" text for the UI
    get characterCount() {
        const currentLength = this._internalValue ? this._internalValue.length : 0;
        return `${currentLength} / ${this.maxLength}`;
    }

    renderedCallback() {
        const textarea = this.template.querySelector('textarea');
        if (textarea) {
            // Imperatively sync DOM value with internal value
            if (textarea.value !== this._internalValue) {
                textarea.value = this._internalValue;
            }
            if (this.isFocused) {
                this.resizeTextarea();
            }
        }
    }

    handleFocus() {
        this.isFocused = true;
        this.resizeTextarea();
    }

    handleInput(event) {
        this._internalValue = event.target.value;
        this.resizeTextarea();

        if (this.required && !this._internalValue) {
            this.hasError = true;
        } else {
            this.hasError = false;
        }

        this.dispatchEvent(new FlowAttributeChangeEvent('value', this._internalValue));
    }

    handleBlur() {
        this.isFocused = false;
        const textarea = this.template.querySelector('textarea');
        if (textarea) {
            textarea.style.height = '';
        }
        if (this.required && !this._internalValue) {
            this.hasError = true;
        }
    }

    @api validate() {
        if (this.required && !this._internalValue) {
            this.hasError = true;
            return { isValid: false, errorMessage: `${this.label} is required.` };
        }
        this.hasError = false;
        return { isValid: true };
    }

    resizeTextarea() {
        const textarea = this.template.querySelector('textarea');
        if (textarea) {
            textarea.style.height = 'auto';
            textarea.style.height = textarea.scrollHeight + 'px';
        }
    }
}