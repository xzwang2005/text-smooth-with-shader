#include "stdafx.h"
#include "Study_MFC.h"
#include "TestSettings.h"

#ifdef _DEBUG
#define new DEBUG_NEW
#undef THIS_FILE
static char THIS_FILE[] = __FILE__;
#endif

IMPLEMENT_DYNAMIC(CTestSettings, CPropertyPage)

CTestSettings::CTestSettings() 
	: CPropertyPage(CTestSettings::IDD)
{}

CTestSettings::CTestSettings(CString fname)
	: CPropertyPage(CTestSettings::IDD)
{
	m_testFolderName = fname;
}

CTestSettings::~CTestSettings() {}

void CTestSettings::DoDataExchange(CDataExchange* pDX)
{
	CPropertyPage::DoDataExchange(pDX);
	//DDX_Control(pDX, IDC_TEST_FOLDER_NAME, m_folderNameCtrl);
	DDX_Control(pDX, IDC_BTN_OPEN_TEST_DIR, m_btnOpenFolder);
}

BEGIN_MESSAGE_MAP(CTestSettings, CPropertyPage)
	ON_BN_CLICKED(IDC_BTN_OPEN_TEST_DIR, &CTestSettings::OnOpenTestFolder)
END_MESSAGE_MAP()

BOOL CTestSettings::OnInitDialog()
{
	CPropertyPage::OnInitDialog();
	GetDlgItem(IDC_TEST_FOLDER_NAME)->SetWindowText(m_testFolderName);
	return TRUE;
}


void CTestSettings::OnOpenTestFolder()
{
	CFolderPickerDialog dlgFolder;
	if (dlgFolder.DoModal() == IDOK)
	{
		m_testFolderName = dlgFolder.GetPathName();
	}
}

void CTestSettings::OnCancel()
{

}