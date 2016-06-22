#pragma once

// CFontSettings dialog
struct FontData {
	COLORREF	fontColor;
	CString		fontName;
	CString		sampleText;
	UINT		minFontSize;
	UINT		maxFontSize;
	FLOAT		magnifyLevel;
	FontData() {};
	FontData(const FontData& pInput) {
		fontColor = pInput.fontColor;
		fontName = pInput.fontName;
		sampleText = pInput.sampleText;
		minFontSize = pInput.minFontSize;
		maxFontSize = pInput.maxFontSize;
		magnifyLevel = pInput.magnifyLevel;
	};
	void deep_copy(const FontData& pInput) {
		fontColor = pInput.fontColor;
		fontName = pInput.fontName;
		sampleText = pInput.sampleText;
		minFontSize = pInput.minFontSize;
		maxFontSize = pInput.maxFontSize;
		magnifyLevel = pInput.magnifyLevel;
	}
	static UINT MaxMagnifyLevel()
	{
		return 12;
	}
};

class CFontSettings : public CPropertyPage
{
	DECLARE_DYNAMIC(CFontSettings)

public:
	CFontSettings();
	CFontSettings(const FontData& data);
	virtual ~CFontSettings();

// Dialog Data
	enum { IDD = IDD_PROPPAGE_SETTINGS };

protected:
	virtual BOOL OnInitDialog();
	virtual void OnCancel();
	//virtual void OnOK();
	//virtual BOOL OnApply();

	virtual void DoDataExchange(CDataExchange* pDX);    // DDX/DDV support

	DECLARE_MESSAGE_MAP()

	afx_msg void OnSelChangeFontName();
	afx_msg void OnTextChange();
	afx_msg void OnBnClickedMfccolorbutton1();
	afx_msg void OnSelChangeMinFontSize();
	afx_msg void OnSelChangeMaxFontSize();
	afx_msg void OnSelChangeMagnify();

private:
	CMFCFontComboBox			m_fontComboboxCtrl;
	CMFCColorButton				m_colorButtonCtrl;
	CComboBox					m_minFontSizeCtrl;
	CComboBox					m_maxFontSizeCtrl;
	CComboBox					m_magnifyCtrl;
	CEdit						m_textBoxCtrl;

	FontData					m_fontDataCpy;

public:
	FontData					m_pFontData;
};
