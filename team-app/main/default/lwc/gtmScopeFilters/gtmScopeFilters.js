import { LightningElement } from 'lwc';
import getFilterOptions from '@salesforce/apex/CockpitWinRateController.getFilterOptions';

const STORE = 'gtmScopeFilters';

export default class GtmScopeFilters extends LightningElement {
    directorId = '';
    teamMode = 'my';
    productType = 'ALL';
    sizeBand = 'ALL';
    directors = [];
    productTypes = [];
    sizeBands = [];
    defaultDirectorName = '';
    ready = false;
    error;

    connectedCallback() {
        const saved = this.readStore();
        getFilterOptions()
            .then((o) => {
                this.directors = this.withKeys(o.directors || []);
                this.productTypes = this.withKeys(o.productTypes || []);
                this.sizeBands = this.withKeys(o.sizeBands || []);
                this.defaultDirectorName = o.defaultDirectorName;
                if (saved) {
                    this.directorId = saved.directorId || '';
                    this.teamMode = saved.teamMode || 'my';
                    this.productType = saved.productType || 'ALL';
                    this.sizeBand = saved.sizeBand || 'ALL';
                }
                this.ready = true;
                this.emit();
            })
            .catch((e) => {
                this.error = (e && e.body && e.body.message) || e.message || 'Could not load filters.';
            });
    }

    get scopeCaption() {
        const dir = this.teamMode === 'my' || !this.directorId
            ? (this.defaultDirectorName || 'My team')
            : this.directorLabel(this.directorId);
        return `Team of ${dir} · ${this.productLabel(this.productType)} · ${this.sizeLabel(this.sizeBand)}`;
    }

    handleDirector(e) {
        this.directorId = e.target.value;
        this.teamMode = this.directorId ? 'director' : 'my';
        this.persistAndEmit();
    }
    handleProduct(e) {
        this.productType = e.target.value;
        this.persistAndEmit();
    }
    handleSize(e) {
        this.sizeBand = e.target.value;
        this.persistAndEmit();
    }

    persistAndEmit() {
        this.writeStore();
        this.emit();
    }

    emit() {
        const detail = {
            directorId: this.directorId || null,
            teamMode: this.teamMode,
            productType: this.productType,
            sizeBand: this.sizeBand
        };
        this.dispatchEvent(new CustomEvent('scopechange', { detail }));
    }

    withKeys(rows) {
        return (rows || []).map((r) => ({
            value: r.value,
            label: r.label,
            key: r.value ? r.value : 'my'
        }));
    }

    directorLabel(id) {
        const hit = (this.directors || []).find((d) => d.value === id);
        return hit ? hit.label : 'Selected director';
    }
    productLabel(v) {
        const hit = (this.productTypes || []).find((d) => d.value === v);
        return hit ? hit.label : 'All products';
    }
    sizeLabel(v) {
        const hit = (this.sizeBands || []).find((d) => d.value === v);
        return hit ? hit.label : 'All sizes';
    }

    readStore() {
        try {
            const raw = sessionStorage.getItem(STORE);
            return raw ? JSON.parse(raw) : null;
        } catch (e) {
            return null;
        }
    }
    writeStore() {
        try {
            sessionStorage.setItem(STORE, JSON.stringify({
                directorId: this.directorId,
                teamMode: this.teamMode,
                productType: this.productType,
                sizeBand: this.sizeBand
            }));
        } catch (e) { /* private mode */ }
    }
}