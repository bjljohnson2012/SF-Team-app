import { LightningElement, api } from 'lwc';
export default class PipelineReviewSavedViews extends LightningElement {
    @api views = [];
    selectedId;
    onPick(e) {
        this.selectedId = e.target.value;
        const v = (this.views || []).find((x) => x.id === this.selectedId);
        if (v) this.dispatchEvent(new CustomEvent('viewload', { detail: v }));
    }
    onSave() { this.dispatchEvent(new CustomEvent('viewsave')); }
    onDup() { this.dispatchEvent(new CustomEvent('viewdup', { detail: this.selectedId })); }
    onDel() { this.dispatchEvent(new CustomEvent('viewdel', { detail: this.selectedId })); }
}
