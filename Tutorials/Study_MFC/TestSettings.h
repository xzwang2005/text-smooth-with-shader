#pragma  once

class CTestSettings :public CPropertyPage{
	DECLARE_DYNAMIC(CTestSettings)

public:
	CTestSettings();
	CTestSettings(CString fname);
	virtual ~CTestSettings();

	// Dialog Data
	enum {IDD = IDD_REG_VERIFY};

protected:
	virtual BOOL OnInitDialog();
	virtual void OnCancel();
	//virtual void OnOK();

	virtual void DoDataExchange(CDataExchange* pDX);    // DDX/DDV support

	DECLARE_MESSAGE_MAP()

	afx_msg void OnOpenTestFolder();

private:
	//CStatic			m_folderNameCtrl;
	CButton			m_btnOpenFolder;

public:
	CString			m_testFolderName;
};
