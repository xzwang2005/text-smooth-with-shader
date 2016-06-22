
// Study_MFCDoc.cpp : implementation of the CStudy_MFCDoc class
//
#include "stdafx.h"
// SHARED_HANDLERS can be defined in an ATL project implementing preview, thumbnail
// and search filter handlers and allows sharing of document code with that project.
#ifndef SHARED_HANDLERS
#include "Study_MFC.h"
#endif

#include "Study_MFCDoc.h"
#include "GeometryDX11.h"
#include "GeometryGeneratorDX11.h"
#include <propkey.h>
#include "TestSettings.h"


#ifdef _DEBUG
#define new DEBUG_NEW
#undef THIS_FILE
static char THIS_FILE[] = __FILE__;
#endif

// CStudy_MFCDoc

IMPLEMENT_DYNCREATE(CStudy_MFCDoc, CDocument)

BEGIN_MESSAGE_MAP(CStudy_MFCDoc, CDocument)
	ON_COMMAND(ID_OPTIONS_SETTINGS, OnSettings)
	ON_COMMAND(ID_TEST_REGRESSIONTEST, OnRegTest)
END_MESSAGE_MAP()


// CStudy_MFCDoc construction/destruction

CStudy_MFCDoc::CStudy_MFCDoc()
{
	// TODO: add one-time construction code here
	pScene = nullptr;
	pActor = nullptr;
	pDiscretePathEffect = nullptr;
}

CStudy_MFCDoc::~CStudy_MFCDoc()
{
}

BOOL CStudy_MFCDoc::OnNewDocument()
{
	if (!CDocument::OnNewDocument())
		return FALSE;

	// TODO: add reinitialization code here
	// (SDI documents will reuse this document)
	m_fontData.fontColor = RGB(0, 0, 0);
	m_fontData.fontName = _T("Arial");
	m_fontData.minFontSize = 12;
	m_fontData.maxFontSize = 24;
	m_fontData.magnifyLevel = 2;
	m_fontData.sampleText = _T("The quick brown fox jumps over the lazy dog. 0123456789");

	pScene = new Glyph3::Scene();
	pActor = new Glyph3::Actor();

	Glyph3::GeometryPtr pGeometry = Glyph3::GeometryPtr(new Glyph3::GeometryDX11());
	Glyph3::GeometryGeneratorDX11::GenerateFullScreenQuad(pGeometry);
	pGeometry->LoadToBuffers();

	// Set up shaders and material
	Glyph3::MaterialPtr pMaterial = Glyph3::MaterialPtr(new Glyph3::MaterialDX11());
	pDiscretePathEffect = new Glyph3::RenderEffectDX11();
	pDiscretePathEffect->SetVertexShader(Glyph3::RendererDX11::Get()->LoadShader(Glyph3::VERTEX_SHADER,
		std::wstring(L"EuclideanPath.hlsl"),
		std::wstring(L"VSMAIN"),
		std::wstring(L"vs_5_0")));
	pDiscretePathEffect->SetPixelShader(Glyph3::RendererDX11::Get()->LoadShader(Glyph3::PIXEL_SHADER,
		std::wstring(L"EuclideanPath.hlsl"),
		std::wstring(L"PS_DISCRETE_PATH_FREEMAN"),
		std::wstring(L"ps_5_0")));

	pFullConnectedDiscretePathEffect = new Glyph3::RenderEffectDX11();
	pFullConnectedDiscretePathEffect->SetVertexShader(Glyph3::RendererDX11::Get()->LoadShader(Glyph3::VERTEX_SHADER,
		std::wstring(L"EuclideanPath.hlsl"),
		std::wstring(L"VSMAIN"),
		std::wstring(L"vs_5_0")));
	pFullConnectedDiscretePathEffect->SetPixelShader(Glyph3::RendererDX11::Get()->LoadShader(Glyph3::PIXEL_SHADER,
		std::wstring(L"EuclideanPath.hlsl"),
		std::wstring(L"PS_ADV_FULL_CONNECTED_POINT"),
		std::wstring(L"ps_5_0")));

	pEuclideanPathEffect = new Glyph3::RenderEffectDX11();
	pEuclideanPathEffect->SetVertexShader(Glyph3::RendererDX11::Get()->LoadShader(Glyph3::VERTEX_SHADER,
		std::wstring(L"EuclideanPath.hlsl"),
		std::wstring(L"VSMAIN"),
		std::wstring(L"vs_5_0")));
	pEuclideanPathEffect->SetPixelShader(Glyph3::RendererDX11::Get()->LoadShader(Glyph3::PIXEL_SHADER,
		std::wstring(L"EuclideanPath.hlsl"),
		std::wstring(L"PS_EUCLIDEAN_PATH_FREEMAN"),
		std::wstring(L"ps_5_0")));

	pMagnifyPathEffect = new Glyph3::RenderEffectDX11();
	pMagnifyPathEffect->SetVertexShader(Glyph3::RendererDX11::Get()->LoadShader(Glyph3::VERTEX_SHADER,
		std::wstring(L"EuclideanPath.hlsl"),
		std::wstring(L"VSMAIN"),
		std::wstring(L"vs_5_0")));
	pMagnifyPathEffect->SetPixelShader(Glyph3::RendererDX11::Get()->LoadShader(Glyph3::PIXEL_SHADER,
		std::wstring(L"EuclideanPath.hlsl"),
		std::wstring(L"PS_MAGNIFY"),
		std::wstring(L"ps_5_0")));

	pFinalEffect = new Glyph3::RenderEffectDX11();
	pFinalEffect->SetVertexShader(Glyph3::RendererDX11::Get()->LoadShader(Glyph3::VERTEX_SHADER,
		std::wstring(L"EuclideanPath.hlsl"),
		std::wstring(L"VSMAIN"),
		std::wstring(L"vs_5_0")));
	pFinalEffect->SetPixelShader(Glyph3::RendererDX11::Get()->LoadShader(Glyph3::PIXEL_SHADER,
		std::wstring(L"EuclideanPath.hlsl"),
		std::wstring(L"PS_FINAL"),
		std::wstring(L"ps_5_0")));

	pMaterial->Params[Glyph3::VT_PERSPECTIVE].bRender = true;
	pMaterial->Params[Glyph3::VT_PERSPECTIVE].pEffect = pDiscretePathEffect;

	pMaterial->Params[Glyph3::VT_LINEAR_DEPTH_NORMAL].bRender = true;
	pMaterial->Params[Glyph3::VT_LINEAR_DEPTH_NORMAL].pEffect = pFullConnectedDiscretePathEffect;

	pMaterial->Params[Glyph3::VT_GBUFFER].bRender = true;
	pMaterial->Params[Glyph3::VT_GBUFFER].pEffect = pEuclideanPathEffect;

	pMaterial->Params[Glyph3::VT_LIGHTS].bRender = true;
	pMaterial->Params[Glyph3::VT_LIGHTS].pEffect = pMagnifyPathEffect;

	pMaterial->Params[Glyph3::VT_FINALPASS].bRender = true;
	pMaterial->Params[Glyph3::VT_FINALPASS].pEffect = pFinalEffect;


	// Create the scene;
	pActor->GetBody()->Visual.SetGeometry(pGeometry);
	pActor->GetBody()->Visual.SetMaterial(pMaterial);

	pScene->AddActor(pActor);
	pScene->Update(0.0f);
	return TRUE;
}

void CStudy_MFCDoc::OnSettings()
{
	CPropertySheet sheet(L"Options");
	CFontSettings m_settingPage(m_fontData);
	sheet.AddPage(&m_settingPage);
	sheet.DoModal();
	m_fontData.deep_copy(m_settingPage.m_pFontData);
	// TODO: update view here
	UpdateAllViews(NULL);
}

void CStudy_MFCDoc::OnRegTest()
{
	CPropertySheet sheet(L"Regression Test");
	CTestSettings m_testSettings(m_testImageFolder);
	sheet.AddPage(&m_testSettings);
	if (sheet.DoModal() == IDOK) {
		m_testImageFolder = m_testSettings.m_testFolderName;
		// run the test
		//RunAugmentationTest();
	}

}

//void CStudy_MFCDoc::SwitchShaderPasses(bool enable)
//{
//	
//}

void CStudy_MFCDoc::RunAugmentationTest()
{
	// stop the 4,5 passes
	// first disable euclidean pass and final pass
	Glyph3::MaterialPtr pMaterial = pActor->GetBody()->Visual.GetMaterial();
	//pMaterial->Params[Glyph3::VT_GBUFFER].bRender = false;
	pMaterial->Params[Glyph3::VT_LIGHTS].bRender = false;
	pMaterial->Params[Glyph3::VT_FINALPASS].bRender = false;
	// setup the test shader for the final pass
	if (pTestAugmentationEffect == nullptr) {
		pTestAugmentationEffect = new Glyph3::RenderEffectDX11();
		pFinalEffect->SetVertexShader(Glyph3::RendererDX11::Get()->LoadShader(Glyph3::VERTEX_SHADER,
			std::wstring(L"EuclideanPath.hlsl"),
			std::wstring(L"VSMAIN"),
			std::wstring(L"vs_5_0")));
		pFinalEffect->SetPixelShader(Glyph3::RendererDX11::Get()->LoadShader(Glyph3::PIXEL_SHADER,
			std::wstring(L"EuclideanPath.hlsl"),
			std::wstring(L"PS_AUGMENT_DIAG"),
			std::wstring(L"ps_5_0")));
	}
	pMaterial->Params[Glyph3::VT_FINALPASS].pEffect = pTestAugmentationEffect;
	//re-enable the final pass
	pMaterial->Params[Glyph3::VT_FINALPASS].bRender = true;

	// run the test here

	//// test finished, restore shaders
	//pMaterial->Params[Glyph3::VT_FINALPASS].bRender = false;
	//pMaterial->Params[Glyph3::VT_FINALPASS].pEffect = false;
	////re-enable the final pass
	//pMaterial->Params[Glyph3::VT_LIGHTS].bRender = true;
	//pMaterial->Params[Glyph3::VT_FINALPASS].bRender = true;
}

// CStudy_MFCDoc serialization

void CStudy_MFCDoc::Serialize(CArchive& ar)
{
	if (ar.IsStoring())
	{
		// TODO: add storing code here
	}
	else
	{
		// TODO: add loading code here
	}
}

void CStudy_MFCDoc::OnCloseDocument()
{
	if (pScene) {
		delete pScene;
	}
	CDocument::OnCloseDocument();
}

#ifdef SHARED_HANDLERS

// Support for thumbnails
void CStudy_MFCDoc::OnDrawThumbnail(CDC& dc, LPRECT lprcBounds)
{
	// Modify this code to draw the document's data
	dc.FillSolidRect(lprcBounds, RGB(255, 255, 255));

	CString strText = _T("TODO: implement thumbnail drawing here");
	LOGFONT lf;

	CFont* pDefaultGUIFont = CFont::FromHandle((HFONT) GetStockObject(DEFAULT_GUI_FONT));
	pDefaultGUIFont->GetLogFont(&lf);
	lf.lfHeight = 36;

	CFont fontDraw;
	fontDraw.CreateFontIndirect(&lf);

	CFont* pOldFont = dc.SelectObject(&fontDraw);
	dc.DrawText(strText, lprcBounds, DT_CENTER | DT_WORDBREAK);
	dc.SelectObject(pOldFont);
}

// Support for Search Handlers
void CStudy_MFCDoc::InitializeSearchContent()
{
	CString strSearchContent;
	// Set search contents from document's data. 
	// The content parts should be separated by ";"

	// For example:  strSearchContent = _T("point;rectangle;circle;ole object;");
	SetSearchContent(strSearchContent);
}

void CStudy_MFCDoc::SetSearchContent(const CString& value)
{
	if (value.IsEmpty())
	{
		RemoveChunk(PKEY_Search_Contents.fmtid, PKEY_Search_Contents.pid);
	}
	else
	{
		CMFCFilterChunkValueImpl *pChunk = NULL;
		ATLTRY(pChunk = new CMFCFilterChunkValueImpl);
		if (pChunk != NULL)
		{
			pChunk->SetTextValue(PKEY_Search_Contents, value, CHUNK_TEXT);
			SetChunkValue(pChunk);
		}
	}
}

#endif // SHARED_HANDLERS

// CStudy_MFCDoc diagnostics

#ifdef _DEBUG
void CStudy_MFCDoc::AssertValid() const
{
	CDocument::AssertValid();
}

void CStudy_MFCDoc::Dump(CDumpContext& dc) const
{
	CDocument::Dump(dc);
}
#endif //_DEBUG


// CStudy_MFCDoc commands
