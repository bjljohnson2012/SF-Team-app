import { LightningElement, api } from 'lwc';
export default class PipelineReviewTable extends LightningElement {
    @api rawRows = [];
    _rows = [];
    @api
    get rows() { return this._rows; }
    set rows(value) {
        this._rows = (value || []).map((r) => ({
            ...r,
            arrLabel: r.arr != null ? '$' + Math.round(r.arr).toLocaleString() : '—',
            gradeClass: 'pill p-' + String(r.grade || 'd').toLowerCase(),
            mismatchClass: r.mismatch ? 'mismatch' : '',
            rowClass: r.selected ? 'selected' : ''
        }));
    }
    onSort(e) { this.dispatchEvent(new CustomEvent('sort', { detail: e.currentTarget.dataset.k })); }
    onPick(e) {
        e.stopPropagation();
        this.dispatchEvent(new CustomEvent('pick', { detail: { id: e.target.dataset.id, selected: e.target.checked } }));
    }
    onTag(e) {
        e.stopPropagation();
        this.dispatchEvent(new CustomEvent('tag', { detail: { id: e.target.dataset.id, tag: e.target.value } }));
    }
    onOpen(e) {
        const id = e.currentTarget.dataset.id;
        const row = (this._rows || []).find((r) => r.id === id);
        this.dispatchEvent(new CustomEvent('open', { detail: row }));
    }
}
