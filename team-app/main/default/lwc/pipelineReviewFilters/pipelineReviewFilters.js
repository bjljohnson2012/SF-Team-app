import { LightningElement, api } from 'lwc';

const FORECASTS = ['Commit', 'Most Likely', 'Best Case', 'Pipeline', 'Omitted'];

export default class PipelineReviewFilters extends LightningElement {
    @api aes = [];
    @api directors = [];
    @api stages = [];
    @api solutions = [];
    _filter = {};
    search = '';
    arrMin = '';
    arrMax = '';
    mismatchOnly = false;

    @api
    get filter() { return this._filter; }
    set filter(value) {
        this._filter = value || {};
        this.search = this._filter.search || '';
        this.arrMin = this._filter.arrMin != null ? this._filter.arrMin : '';
        this.arrMax = this._filter.arrMax != null ? this._filter.arrMax : '';
        this.mismatchOnly = this._filter.mismatchOnly === true;
        this.syncSelects();
    }

    get forecasts() { return FORECASTS; }
    get directorOptions() { return this.directors || []; }

    renderedCallback() { this.syncSelects(); }

    syncSelects() {
        const f = this._filter || {};
        this.setSel('directorId', f.directorId || '');
        this.setSel('ownerId', (f.ownerIds && f.ownerIds[0]) || '');
        this.setSel('stage', (f.stages && f.stages[0]) || '');
        this.setSel('solution', (f.solutions && f.solutions[0]) || '');
        this.setSel('tag', (f.tags && f.tags[0]) || '');
        this.setSel('staleness', (f.staleness && f.staleness[0]) || '');
        this.setSel('runState', (f.runStates && f.runStates[0]) || '');
        this.setSel('nextStep', (f.nextStepStates && f.nextStepStates[0]) || '');
        this.setSel('aeForecast', (f.aeForecasts && f.aeForecasts[0]) || '');
        this.setSel('directorForecast', (f.directorForecasts && f.directorForecasts[0]) || '');
        this.setSel('recommended', (f.recommendedForecasts && f.recommendedForecasts[0]) || '');
        this.setSel('closePreset', f.closePreset || '');
    }
    setSel(key, value) {
        const el = this.template.querySelector('select[data-k="' + key + '"]');
        if (el && el.value !== String(value || '')) el.value = value || '';
    }
    emit(partial) { this.dispatchEvent(new CustomEvent('filterchange', { detail: partial })); }
    one(v) { return v ? [v] : []; }
    onDirector(e) { this.emit({ directorId: e.target.value || null, ownerIds: [] }); }
    onAe(e) { this.emit({ ownerIds: this.one(e.target.value) }); }
    onStage(e) { this.emit({ stages: this.one(e.target.value) }); }
    onSolution(e) { this.emit({ solutions: this.one(e.target.value) }); }
    onTag(e) { this.emit({ tags: this.one(e.target.value) }); }
    onStale(e) { this.emit({ staleness: this.one(e.target.value) }); }
    onRun(e) { this.emit({ runStates: this.one(e.target.value) }); }
    onNext(e) { this.emit({ nextStepStates: this.one(e.target.value) }); }
    onAeFc(e) { this.emit({ aeForecasts: this.one(e.target.value) }); }
    onDirFc(e) { this.emit({ directorForecasts: this.one(e.target.value) }); }
    onRec(e) { this.emit({ recommendedForecasts: this.one(e.target.value) }); }
    onClose(e) {
        const preset = e.target.value;
        const range = this.closeRange(preset);
        this.emit({ closePreset: preset, closeFrom: range.from, closeTo: range.to });
    }
    onMismatch(e) { this.mismatchOnly = e.target.checked; this.emit({ mismatchOnly: e.target.checked }); }
    onArr(e) {
        const minEl = this.template.querySelector('input[data-k="arrMin"]');
        const maxEl = this.template.querySelector('input[data-k="arrMax"]');
        this.arrMin = minEl ? minEl.value : '';
        this.arrMax = maxEl ? maxEl.value : '';
        window.clearTimeout(this._arrT);
        this._arrT = window.setTimeout(() => {
            this.emit({
                arrMin: this.arrMin === '' ? null : Number(this.arrMin),
                arrMax: this.arrMax === '' ? null : Number(this.arrMax)
            });
        }, 350);
    }
    onSearch(e) {
        this.search = e.target.value;
        window.clearTimeout(this._t);
        this._t = window.setTimeout(() => this.emit({ search: this.search }), 250);
    }
    closeRange(preset) {
        const today = new Date();
        const y = today.getFullYear();
        const m = today.getMonth();
        const iso = (d) => d.toISOString().slice(0, 10);
        if (preset === 'thisQ') {
            const q = Math.floor(m / 3) * 3;
            return { from: iso(new Date(y, q, 1)), to: iso(new Date(y, q + 3, 0)) };
        }
        if (preset === 'nextQ') {
            const q = Math.floor(m / 3) * 3 + 3;
            return { from: iso(new Date(y, q, 1)), to: iso(new Date(y, q + 3, 0)) };
        }
        if (preset === 'thisM') {
            return { from: iso(new Date(y, m, 1)), to: iso(new Date(y, m + 1, 0)) };
        }
        if (preset === 'past') {
            const yest = new Date(y, m, today.getDate() - 1);
            return { from: null, to: iso(yest) };
        }
        return { from: null, to: null };
    }
}
