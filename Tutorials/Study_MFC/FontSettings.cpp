// FontSettings.cpp : implementation file
//

#include "stdafx.h"
#include "Study_MFC.h"
#include "FontSettings.h"
#include "afxdialogex.h"

#ifdef _DEBUG
#define new DEBUG_NEW
#undef THIS_FILE
static char THIS_FILE[] = __FILE__;
#endif

#define FIRST_MIN_FONT_SIZE 8
#define FIRST_MAX_FONT_SIZE 18
// CFontSettings dialog

IMPLEMENT_DYNAMIC(CFontSettings, CPropertyPage)

CFontSettings::CFontSettings()
	: CPropertyPage(CFontSettings::IDD)
{
}

CFontSettings::CFontSettings(const FontData& data)
	: CPropertyPage(CFontSettings::IDD)
{
	m_pFontData.deep_copy(data);
}

CFontSettings::~CFontSettings()
{
}

void CFontSettings::DoDataExchange(CDataExchange* pDX)
{
	CPropertyPage::DoDataExchange(pDX);
	DDX_Control(pDX, IDC_MFCFONTCOMBO1, m_fontComboboxCtrl);
	DDX_Control(pDX, IDC_MFCCOLORBUTTON1, m_colorButtonCtrl);
	DDX_Control(pDX, IDC_SAMPLE_TEXT, m_textBoxCtrl);
	DDX_Control(pDX, IDC_COMBO_MIN_FONT_SIZE, m_minFontSizeCtrl);
	DDX_Control(pDX, IDC_COMBO_MAX_FONT_SIZE, m_maxFontSizeCtrl);
	DDX_Control(pDX, IDC_COMBO_MAGNIFY, m_magnifyCtrl);
}


BEGIN_MESSAGE_MAP(CFontSettings, CPropertyPage)
	ON_CBN_SELCHANGE(IDC_MFCFONTCOMBO1, &CFontSettings::OnSelChangeFontName)
	ON_CBN_SELCHANGE(IDC_COMBO_MIN_FONT_SIZE, &CFontSettings::OnSelChangeMinFontSize)
	ON_CBN_SELCHANGE(IDC_COMBO_MAX_FONT_SIZE, &CFontSettings::OnSelChangeMaxFontSize)
	ON_CBN_SELCHANGE(IDC_COMBO_MAGNIFY, &CFontSettings::OnSelChangeMagnify)
	ON_EN_UPDATE(IDC_SAMPLE_TEXT, &CFontSettings::OnTextChange)
	ON_BN_CLICKED(IDC_MFCCOLORBUTTON1, &CFontSettings::OnBnClickedMfccolorbutton1)
END_MESSAGE_MAP()


// CFontSettings message handlers
BOOL CFontSettings::OnInitDialog()
{
	CPropertyPage::OnInitDialog();
	m_fontDataCpy.deep_copy(m_pFontData);
	for (UINT sz = 0; sz <= 16; sz++) {
		CString chsz;
		chsz.Format(_T("%u"), sz + FIRST_MIN_FONT_SIZE);
		m_minFontSizeCtrl.AddString(chsz);
		if (sz + FIRST_MIN_FONT_SIZE == m_pFontData.minFontSize) {
			m_minFontSizeCtrl.SetCurSel(sz);
		}
	}

	for (UINT sz = 0; sz <= 20; sz++) {
		CString chsz;
		chsz.Format(_T("%u"), sz + FIRST_MAX_FONT_SIZE);
		m_maxFontSizeCtrl.AddString(chsz);
		if (sz + FIRST_MAX_FONT_SIZE == m_pFontData.maxFontSize) {
			m_maxFontSizeCtrl.SetCurSel(sz);
		}
	}

	for (UINT mag = 1; mag <= FontData::MaxMagnifyLevel(); mag++) {
		CString chsz;
		chsz.Format(_T("%u"), mag);
		m_magnifyCtrl.AddString(chsz);
		if (mag == m_pFontData.magnifyLevel) {
			m_magnifyCtrl.SetCurSel(mag - 1);
		}
	}

	m_fontComboboxCtrl.SelectFont(m_pFontData.fontName);
	m_textBoxCtrl.SetWindowText(m_pFontData.sampleText);
	m_colorButtonCtrl.SetColor(m_pFontData.fontColor );

	return TRUE;
}

void CFontSettings::OnSelChangeFontName()
{
	m_pFontData.fontName = m_fontComboboxCtrl.GetSelFont()->m_strName;
}

void CFontSettings::OnTextChange()
{
	CString newText;
	m_textBoxCtrl.GetWindowTextW(newText);
	m_pFontData.sampleText = newText;
}

void CFontSettings::OnCancel()
{
	m_pFontData.deep_copy(m_fontDataCpy);
}


void CFontSettings::OnBnClickedMfccolorbutton1()
{
	// TODO: Add your control notification handler code here
	m_pFontData.fontColor = m_colorButtonCtrl.GetColor();
}

void CFontSettings::OnSelChangeMinFontSize()
{
	int value = FIRST_MIN_FONT_SIZE + m_minFontSizeCtrl.GetCurSel();
	if (value > m_pFontData.maxFontSize) return;
	m_pFontData.minFontSize = value;
}

void CFontSettings::OnSelChangeMaxFontSize()
{
	int value = FIRST_MAX_FONT_SIZE + m_maxFontSizeCtrl.GetCurSel();
	if (value < m_pFontData.minFontSize) return;
	m_pFontData.maxFontSize = value;
}

void CFontSettings::OnSelChangeMagnify()
{
	m_pFontData.magnifyLevel = m_magnifyCtrl.GetCurSel() + 1;
}