import { LightningElement, api } from 'lwc';

const TAGS = ['A', 'B', 'C', 'D', ''];

export default class PipelineReviewTable extends LightningElement {
    _rows = [];
    @api
    get rows() { return this._rows; }
    set rows(value) {
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        this._rows = (value || []).map((r) => this.decorate(r, today));
    }
    get isEmpty() { return !this._rows || this._rows.length === 0; }
    get allSelected() { return this._rows.length > 0 && this._rows.every((r) => r.selected); }

    decorate(r, today) {
        const close = r.closeDate ? new Date(r.closeDate) : null;
        if (close) close.setHours(0, 0, 0, 0);
        const left = close ? Math.round((close - today) / 86400000) : null;
        const tag = (r.tag || r.grade || '').toUpperCase();
        const note = (r.note || '').replace(/\s+/g, ' ').trim();
        return {
            ...r,
            tagLabel: tag || '–',
            tagClass: 'tag t-' + (tag || 'x').toLowerCase(),
            arrLabel: r.arr != null ? '$' + Math.round(r.arr).toLocaleString() : '—',
            closeLabel: this.fmtDate(r.closeDate),
            closeLeft: left == null ? '' : (left >= 0 ? left + ' left' : Math.abs(left) + ' overdue'),
            subline: [r.name && r.name !== r.account ? r.name : '', r.solution].filter(Boolean).join(' · '),
            noteLabel: note || 'No director note on record',
            aeForecastLabel: r.aeForecast || '—',
            directorForecastLabel: r.directorForecast || 'not set',
            recommendedForecastLabel: r.recommendedForecast || '—',
            aePillClass: 'pill ' + this.fcClass(r.aeForecast),
            dirPillClass: 'pill ' + this.fcClass(r.directorForecast),
            recPillClass: 'pill ' + this.fcClass(r.recommendedForecast),
            staleDotClass: 'dot ' + this.ageClass(r.freshestAge),
            dueDotClass: 'tri ' + (r.nextStepState === 'PastDue' ? 'hot' : 'ok'),
            staleTitle: r.freshestAge == null ? 'Activity age unknown' : r.freshestAge + ' days since activity',
            dueTitle: r.nextStepState || 'Next step',
            runLabel: this.fmtDate(r.nextStepDate) || 'n/k',
            runSub: r.nextStepState || '',
            rowClass: r.selected ? 'selected' : ''
        };
    }
    fcClass(v) {
        const n = String(v || '').toLowerCase();
        if (n === 'commit' || n === 'forecast') return 'p-com';
        if (n.indexOf('most') === 0) return 'p-ml';
        if (n.indexOf('best') === 0) return 'p-bc';
        if (n === 'omitted') return 'p-om';
        return 'p-pipe';
    }
    ageClass(days) {
        if (days == null) return 'unk';
        if (days <= 7) return 'ok';
        if (days <= 21) return 'mid';
        return 'hot';
    }
    fmtDate(v) {
        if (!v) return '';
        const d = new Date(v);
        if (Number.isNaN(d.getTime())) return String(v);
        return d.toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' });
    }
    onSort(e) { this.dispatchEvent(new CustomEvent('sort', { detail: e.currentTarget.dataset.k })); }
    onPick(e) {
        e.stopPropagation();
        this.dispatchEvent(new CustomEvent('pick', { detail: { id: e.target.dataset.id, selected: e.target.checked } }));
    }
    onPickAll(e) {
        e.stopPropagation();
        this.dispatchEvent(new CustomEvent('pickall', { detail: { selected: e.target.checked } }));
    }
    onTagCycle(e) {
        e.stopPropagation();
        const id = e.currentTarget.dataset.id;
        const row = (this._rows || []).find((r) => r.id === id);
        const cur = (row && (row.tag || row.grade) || '').toUpperCase();
        const idx = TAGS.indexOf(cur);
        const next = TAGS[(idx + 1) % TAGS.length];
        this.dispatchEvent(new CustomEvent('tag', { detail: { id, tag: next } }));
    }
    onOpen(e) {
        const id = e.currentTarget.dataset.id;
        const row = (this._rows || []).find((r) => r.id === id);
        this.dispatchEvent(new CustomEvent('open', { detail: row }));
    }
}
