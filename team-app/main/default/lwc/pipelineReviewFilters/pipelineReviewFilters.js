import { LightningElement, api } from 'lwc';
const FORECASTS = ['Commit', 'Most Likely', 'Best Case', 'Pipeline', 'Omitted'];
export default class PipelineReviewFilters extends LightningElement {
    @api aes = [];
    search = '';
    get forecasts() { return FORECASTS; }
    selected(e) { return [...e.target.selectedOptions].map((o) => o.value); }
    emit(partial) { this.dispatchEvent(new CustomEvent('filterchange', { detail: partial })); }
    onOwners(e) { this.emit({ ownerIds: this.selected(e) }); }
    onAeFc(e) { this.emit({ aeForecasts: this.selected(e) }); }
    onRec(e) { this.emit({ recommendedForecasts: this.selected(e) }); }
    onState(e) { this.emit({ nextStepStates: this.selected(e) }); }
    onMismatch(e) { this.emit({ mismatchOnly: e.target.value === '1' }); }
    onSearch(e) {
        this.search = e.target.value;
        window.clearTimeout(this._t);
        this._t = window.setTimeout(() => this.emit({ search: this.search }), 250);
    }
}
