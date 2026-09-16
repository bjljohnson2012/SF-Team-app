/**
 * Minimal pure-Apex ZIP writer (STORE method, no compression) for assembling
 * Open Packaging Convention archives such as .docx. Apex has no ZIP library and
 * Word accepts stored (uncompressed) entries, so this builds a valid archive by
 * emitting the local headers, central directory and end-of-central-directory
 * records as hex, then converting to a Blob. Entries are written in list order.
 */
public class DocxZip {
    private static final String HD = '0123456789abcdef';
    private static Long[] table;

    private static void initCrc() {
        if (table != null) return;
        table = new List<Long>();
        for (Integer n = 0; n < 256; n++) {
            Long c = n;
            for (Integer k = 0; k < 8; k++) { c = ((c & 1) == 1) ? (3988292384L ^ (c >>> 1)) : (c >>> 1); }
            table.add(c & 4294967295L);
        }
    }
    private static String byteHex(Integer b) {
        Integer hi = (b >> 4) & 15, lo = b & 15;
        return HD.substring(hi, hi + 1) + HD.substring(lo, lo + 1);
    }
    private static String leHex(Long v, Integer nbytes) {
        String o = '';
        for (Integer i = 0; i < nbytes; i++) o += byteHex((Integer)((v >> (8 * i)) & 255));
        return o;
    }
    private static Long crc32(Blob data) {
        String h = EncodingUtil.convertToHex(data);
        Long crc = 4294967295L;
        for (Integer i = 0; i < h.length(); i += 2) {
            Integer bv = HD.indexOf(h.substring(i, i + 1)) * 16 + HD.indexOf(h.substring(i + 1, i + 2));
            crc = table[(Integer)((crc ^ bv) & 255)] ^ (crc >>> 8);
        }
        return (crc ^ 4294967295L) & 4294967295L;
    }

    /** Builds a ZIP Blob from the named entries, in the given order. */
    public static Blob build(List<String> names, Map<String, Blob> files) {
        initCrc();
        String local = '', central = '';
        Integer offset = 0;
        for (String nm : names) {
            Blob data = files.get(nm);
            Long crc = crc32(data);
            String nameHex = EncodingUtil.convertToHex(Blob.valueOf(nm));
            String dataHex = EncodingUtil.convertToHex(data);
            Integer nameLen = Blob.valueOf(nm).size();
            Integer dataLen = data.size();
            local += '504b0304' + leHex(20, 2) + leHex(0, 2) + leHex(0, 2) + leHex(0, 2) + leHex(0, 2)
                + leHex(crc, 4) + leHex(dataLen, 4) + leHex(dataLen, 4) + leHex(nameLen, 2) + leHex(0, 2) + nameHex + dataHex;
            central += '504b0102' + leHex(20, 2) + leHex(20, 2) + leHex(0, 2) + leHex(0, 2) + leHex(0, 2) + leHex(0, 2)
                + leHex(crc, 4) + leHex(dataLen, 4) + leHex(dataLen, 4) + leHex(nameLen, 2) + leHex(0, 2) + leHex(0, 2)
                + leHex(0, 2) + leHex(0, 2) + leHex(0, 4) + leHex(offset, 4) + nameHex;
            offset += 30 + nameLen + dataLen;
        }
        Integer cdSize = central.length() / 2;
        String eocd = '504b0506' + leHex(0, 2) + leHex(0, 2) + leHex(names.size(), 2) + leHex(names.size(), 2)
            + leHex(cdSize, 4) + leHex(offset, 4) + leHex(0, 2);
        return EncodingUtil.convertFromHex(local + central + eocd);
    }
}
