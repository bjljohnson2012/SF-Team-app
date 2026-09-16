import { LightningElement, api } from 'lwc';
export default class PipelineReviewToolbar extends LightningElement {
    @api lastUpdated;
    @api banner;
    @api skipLine = '';
    get lastUpdatedLabel() {
        return this.lastUpdated ? new Date(this.lastUpdated).toLocaleString() : 'not yet graded';
    }
    onRegen() { this.dispatchEvent(new CustomEvent('regen')); }
    onExport() { this.dispatchEvent(new CustomEvent('export')); }
}
