import { LightningElement, api } from 'lwc';
export default class PipelineReviewDrawer extends LightningElement {
    @api row;
    @api preview;
    @api error;
    note = '';
    _rowId;
    renderedCallback() {
        if (this.row && this.row.id !== this._rowId) {
            this._rowId = this.row.id;
            this.note = this.row.note || '';
        }
    }
    onNote(e) { this.note = e.target.value; }
    onSave() { this.dispatchEvent(new CustomEvent('savenote', { detail: { id: this.row.id, note: this.note } })); }
    onRegen() { this.dispatchEvent(new CustomEvent('regenone', { detail: this.row.id })); }
    onClose() { this.dispatchEvent(new CustomEvent('close')); }
}
