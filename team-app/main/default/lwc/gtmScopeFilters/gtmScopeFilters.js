import { LightningElement, api } from 'lwc';
import getFilterOptions from '@salesforce/apex/CockpitWinRateController.getFilterOptions';

const STORE = 'gtmScopeFilters';
const STORE_GROUPED = 'gtmScopeFiltersGrouped';
const PRODUCT_ALL = 'ALL';
const SIZE_ALL = 'ALL';

export default class GtmScopeFilters extends LightningElement {
    @api groupedProducts = false;
    directorId = '';
    teamMode = 'my';
    productType = PRODUCT_ALL;
    sizeBand = SIZE_ALL;
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
                const products = this.groupedProducts
                    ? (o.productGroups || o.productTypes)
                    : o.productTypes;
                this.productTypes = this.withKeys(products || []);
                this.sizeBands = this.withKeys(o.sizeBands || []);
                this.defaultDirectorName = o.defaultDirectorName;
                if (saved) {
                    this.directorId = saved.directorId || '';
                    this.teamMode = saved.teamMode || 'my';
                }
                this.productType = PRODUCT_ALL;
                this.sizeBand = SIZE_ALL;
                if (saved) {
                    const known = new Set((this.productTypes || []).map((p) => p.value));
                    const sizes = new Set((this.sizeBands || []).map((s) => s.value));
                    if (saved.productType && known.has(saved.productType)) {
                        this.productType = saved.productType;
                    }
                    if (saved.sizeBand && sizes.has(saved.sizeBand)) {
                        this.sizeBand = saved.sizeBand;
                    }
                }
                this.ready = true;
                this.writeStore();
                this.emit();
            })
            .catch((e) => {
                this.error = (e && e.body && e.body.message) || e.message || 'Could not load filters.';
                this.ready = true;
                this.emit();
            });
    }

    get directorSelectOptions() {
        return (this.directors || []).map((d) => ({
            ...d,
            selected: (d.value || '') === (this.directorId || '')
        }));
    }
    get productSelectOptions() {
        return (this.productTypes || []).map((d) => ({
            ...d,
            selected: d.value === this.productType
        }));
    }
    get sizeSelectOptions() {
        return (this.sizeBands || []).map((d) => ({
            ...d,
            selected: d.value === this.sizeBand
        }));
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
        this.productType = e.target.value || PRODUCT_ALL;
        this.persistAndEmit();
    }
    handleSize(e) {
        this.sizeBand = e.target.value || SIZE_ALL;
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
            productType: this.productType || PRODUCT_ALL,
            sizeBand: this.sizeBand || SIZE_ALL
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
    storeKey() {
        return this.groupedProducts ? STORE_GROUPED : STORE;
    }
    productLabel(v) {
        if (!v || v === PRODUCT_ALL) return 'All products';
        const hit = (this.productTypes || []).find((d) => d.value === v);
        return hit ? hit.label : 'All products';
    }
    sizeLabel(v) {
        const hit = (this.sizeBands || []).find((d) => d.value === v);
        return hit ? hit.label : 'All sizes';
    }

    readStore() {
        try {
            const raw = sessionStorage.getItem(this.storeKey());
            return raw ? JSON.parse(raw) : null;
        } catch (e) {
            return null;
        }
    }
    writeStore() {
        try {
            sessionStorage.setItem(this.storeKey(), JSON.stringify({
                directorId: this.directorId,
                teamMode: this.teamMode,
                productType: this.productType || PRODUCT_ALL,
                sizeBand: this.sizeBand || SIZE_ALL
            }));
        } catch (e) { /* private mode */ }
    }
}
