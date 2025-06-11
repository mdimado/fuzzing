/*
 * Fuzz target for goipp's getStrings method on IPP attributes.
 */

func FuzzIppAttrsGetStrings(f *testing.F) {
	f.Fuzz(func(t *testing.T, data []byte) {
		// split data into two parts: name and value
		parts := bytes.SplitN(data, []byte{'\n'}, 2)
		if len(parts) < 2 {
			t.Skip() // not enough input
		}

		attrName := string(parts[0])
		attrValue := string(parts[1])

		// make fake IPP attribute
		attrs := goipp.Attributes{
			goipp.MakeAttr(attrName, goipp.TagText, goipp.String(attrValue)),
		}

		// wrap it in helper and call getStrings
		ippAttrs := newIppAttrs(attrs)
		result := ippAttrs.getStrings(attrName)

		// if there's a result, check if it looks right
		if result != nil && len(result) > 0 {
			if result[0] != attrValue && attrValue != "" {
				t.Logf("Unexpected result for %s: got %v, expected %s", attrName, result, attrValue)
			}
		}
	})
}
